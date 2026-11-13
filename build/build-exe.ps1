<#
  Compila KoeDL.exe e KoeDL-Setup.exe a partir das fontes, do mesmo jeito que o
  KoeDL.bat faz em tempo de execucao (CodeDom -> csc). Serve para o CI publicar o
  instalador sem abrir o app.

  Precisa rodar no Windows, com o csc.exe do .NET Framework 4:

      powershell -NoProfile -ExecutionPolicy Bypass -File build/build-exe.ps1 -OutDir dist

  O .bat e gerado antes, a menos que -SkipBuild seja usado.
#>
param(
    [string]$Root = (Split-Path $PSScriptRoot -Parent),
    [string]$OutDir = 'dist',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture

function Get-Csc {
    $roots = @("$env:WINDIR\Microsoft.NET\Framework64", "$env:WINDIR\Microsoft.NET\Framework")
    foreach ($root in $roots) {
        foreach ($ver in @('v4.0.30319', 'v3.5')) {
            $exe = Join-Path $root "$ver\csc.exe"
            if (Test-Path $exe) { return $exe }
        }
    }
    $cmd = Get-Command csc.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw 'csc.exe (.NET Framework) nao encontrado nesta maquina.'
}

function Invoke-Csc([string]$csc, [string]$src, [string]$setup, [string]$ico, [string]$payload, [string]$logo, [string]$out) {
    $cscArgs = @(
        '/nologo', '/target:winexe', '/optimize',
        "/win32icon:$ico",
        "/resource:$payload",
        "/resource:$logo",
        '/r:System.dll', '/r:System.Windows.Forms.dll', '/r:System.Drawing.dll',
        "/out:$out", $src, $setup
    )
    $lines = & $csc @cscArgs 2>&1
    return [pscustomobject]@{ ok = ($LASTEXITCODE -eq 0 -and (Test-Path $out)); output = @($lines) }
}

if (-not $SkipBuild) {
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }
    if (-not $py) { throw 'python nao encontrado; rode o build do .bat antes ou use -SkipBuild.' }
    & $py.Source (Join-Path $Root 'build/build.py')
    if ($LASTEXITCODE -ne 0) { throw 'build/build.py falhou.' }
}

$bat = Join-Path $Root 'KoeDL.bat'
if (-not (Test-Path $bat)) { throw "KoeDL.bat nao encontrado em $bat" }

$raw = [IO.File]::ReadAllText($bat, [Text.Encoding]::UTF8)
$marker = '###' + 'PS###'
$ix = $raw.LastIndexOf($marker)
if ($ix -lt 0) { throw "KoeDL.bat sem o marcador $marker" }
$payload = $raw.Substring($ix + $marker.Length)

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('koedl_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $tmp | Out-Null
try {
    $pf = Join-Path $tmp 'payload.ps1'
    [IO.File]::WriteAllText($pf, $payload, (New-Object Text.UTF8Encoding $false))
    $ico = Join-Path $Root 'assets/app.ico'
    $lg = Join-Path $tmp 'logo.png'
    Copy-Item (Join-Path $Root 'assets/logo-window.png') $lg -Force

    $csc = Get-Csc
    $appWv = Join-Path $Root 'src/backend/csharp/App.WebView2.cs'
    $appBasic = Join-Path $Root 'src/backend/csharp/App.Basic.cs'
    $setupCs = Join-Path $Root 'src/backend/csharp/Setup.cs'

    $out = Join-Path $tmp 'KoeDL.exe'
    $tier1 = Invoke-Csc $csc $appWv $setupCs $ico $pf $lg $out
    if ($tier1.ok) {
        Write-Host 'exe: compilado com a janela WebView2 (tier 1).'
    }
    else {
        Write-Host 'exe: o tier 1 falhou; tentando sem WebView2 (tier 2).'
        $tier1.output | Select-Object -First 12 | ForEach-Object { Write-Host "  $_" }
        $tier2 = Invoke-Csc $csc $appBasic $setupCs $ico $pf $lg $out
        if (-not $tier2.ok) {
            $tier2.output | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
            throw 'o exe nao compilou em nenhum dos dois modos.'
        }
        Write-Host 'exe: compilado sem a janela WebView2 (tier 2).'
    }

    if (-not [IO.Path]::IsPathRooted($OutDir)) { $OutDir = Join-Path $Root $OutDir }
    New-Item -ItemType Directory -Force $OutDir | Out-Null
    foreach ($name in 'KoeDL.exe', 'KoeDL-Setup.exe') {
        Copy-Item $out (Join-Path $OutDir $name) -Force
    }
    foreach ($name in 'KoeDL.bat', 'Media-Downloader.bat', 'koedl.sh') {
        Copy-Item (Join-Path $Root $name) (Join-Path $OutDir $name) -Force
    }

    $lines = foreach ($name in 'KoeDL.bat', 'Media-Downloader.bat', 'koedl.sh', 'KoeDL.exe', 'KoeDL-Setup.exe') {
        $hash = (Get-FileHash (Join-Path $OutDir $name) -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Host ("{0}  {1}" -f $hash, $name)
        "{0}  {1}" -f $hash, $name
    }
    [IO.File]::WriteAllLines((Join-Path $OutDir 'SHA256SUMS.txt'), $lines, (New-Object Text.UTF8Encoding $false))
    Write-Host "artefatos em $OutDir"
}
finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
