function Bg($sb,$a){ $rsp=[runspacefactory]::CreateRunspace(); $rsp.Open(); $p=[powershell]::Create(); $p.Runspace=$rsp
 [void]$p.AddScript($sb.ToString()); foreach($x in $a){ [void]$p.AddArgument($x) }; [void]$p.BeginInvoke() }
function ReadSettings{ if(Test-Path $settingsFile){ try{ return (Get-Content $settingsFile -Raw -Encoding UTF8|ConvertFrom-Json) }catch{ if(-not $script:warnCfg){ $script:warnCfg=$true; L "[config] nao consegui ler o settings.json: $($_.Exception.Message)" } } }; return $null }
function GetDl{ $s=ReadSettings; $d=$null; if($s -and $s.dlDir){ $d="$($s.dlDir)".Trim() }
 if(-not $d){ $d=$(if($env:YTDL_INSTALLED){ $(if((-not(Test-Path ([IO.Path]::Combine($env:USERPROFILE,'Downloads','KoeDL')))) -and (Test-Path ([IO.Path]::Combine($env:USERPROFILE,'Downloads','Media Downloader')))){ [IO.Path]::Combine($env:USERPROFILE,'Downloads','Media Downloader') }else{ [IO.Path]::Combine($env:USERPROFILE,'Downloads','KoeDL') }) }else{ [IO.Path]::Combine($dir,'Downloads') }) }
 try{ New-Item -ItemType Directory -Force $d | Out-Null }catch{ $d=[IO.Path]::Combine($dir,'Downloads'); New-Item -ItemType Directory -Force $d | Out-Null }
 return $d }
function DlRoots{ $sj=ReadSettings; $r=@((GetDl)); if($sj){ foreach($k in 'dirAudio','dirVideo'){ if("$($sj.$k)".Trim()){ $r+="$($sj.$k)".Trim() } }
 if($sj.PSObject.Properties['libDirs']){ foreach($d in @($sj.libDirs)){ if("$d".Trim()){ $r+="$d".Trim() } } } }; return ,$r }
function LibDirs{ $sj=ReadSettings; $r=@(); if($sj -and $sj.PSObject.Properties['libDirs']){ foreach($d in @($sj.libDirs)){ if("$d".Trim()){ $r+="$d".Trim() } } }; return $r }
function SaveLibDirs($arr){
 $sj=$null; try{ if(Test-Path $settingsFile){ $sj=Get-Content $settingsFile -Raw -Encoding UTF8|ConvertFrom-Json } }catch{}
 if(-not $sj){ $sj=[pscustomobject]@{} }
 $o=@(); foreach($d in @($arr)){ if("$d".Trim()){ $o+="$d".Trim() } }
 $sj|Add-Member -NotePropertyName libDirs -NotePropertyValue ([object[]]$o) -Force
 [IO.File]::WriteAllText($settingsFile,(ConvertTo-Json -InputObject $sj -Depth 6),(New-Object Text.UTF8Encoding $false))
 return $o }
function SetLibDirs($list){
 # Normaliza, descarta repetidas, confere que a pasta existe e grava em settings.json (limite de 20 pastas).
 $o=@(); $seen=@{}
 foreach($d in @($list)){ $t="$d".Trim(); if(-not $t){ continue }
  $fp=$null; try{ $fp=[IO.Path]::GetFullPath($t) }catch{ throw (Tr "Caminho invalido: $t" "Invalid path: $t") }
  if(-not (Test-Path -LiteralPath $fp -PathType Container)){ throw (Tr "Pasta nao encontrada: $t" "Folder not found: $t") }
  $fp=$fp.TrimEnd('\','/'); $k=$fp.ToLowerInvariant(); if($seen.ContainsKey($k)){ continue }; $seen[$k]=1
  if($o.Count -ge 20){ break }; $o+=$fp }
 return (SaveLibDirs $o) }
function StartLibPick{
 # O seletor nativo roda em outro processo -STA para nao travar o servidor da interface.
 $S.libPick='run'; $S.libPickErr=''
 $f=J $bin 'libpick.ps1'; $o=J $bin 'libpick.out'; Remove-Item $o -ea 0
 $sc=@'
Add-Type -AssemblyName System.Windows.Forms | Out-Null
$o=$args[0]
try{
 $d=New-Object Windows.Forms.FolderBrowserDialog
 $d.Description='Escolha a pasta que o KoeDL deve mostrar na Biblioteca'
 $d.ShowNewFolderButton=$true
 $f=New-Object Windows.Forms.Form
 $f.TopMost=$true; $f.ShowInTaskbar=$false; $f.Width=1; $f.Height=1; $f.StartPosition='CenterScreen'; $f.Opacity=0
 $f.Show()
 $r=$d.ShowDialog($f)
 $f.Close()
 if($r -eq [Windows.Forms.DialogResult]::OK){ [IO.File]::WriteAllText($o,$d.SelectedPath) } else { [IO.File]::WriteAllText($o,'') }
}catch{ try{ [IO.File]::WriteAllText($o,'') }catch{} }
'@
 [IO.File]::WriteAllText($f,$sc,(New-Object Text.UTF8Encoding $true))
 $psi=New-Object Diagnostics.ProcessStartInfo 'powershell.exe'
 $psi.Arguments='-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$f+'" "'+$o+'"'
 $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
 $S.libPickPid=([Diagnostics.Process]::Start($psi)).Id }
function CheckLibPick{
 # Chamado pelo GET /api/libadd: a janela fechou (ou foi cancelada), entao a pasta escolhida entra na lista.
 if(-not $S.libPick){ return }
 $o=J $bin 'libpick.out'
 if(Test-Path $o){
  $p=''; try{ $p=[IO.File]::ReadAllText($o).Trim() }catch{}
  Remove-Item $o -ea 0; $S.libPick=''; $S.libPickPid=0
  if($p){ try{ [void](SetLibDirs (@(LibDirs)+$p)) }catch{ $S.libPickErr=$_.Exception.Message } }
  return }
 $alive=$false; try{ if($S.libPickPid){ $alive=([Diagnostics.Process]::GetProcessById([int]$S.libPickPid) -ne $null) } }catch{ $alive=$false }
 if(-not $alive){ $S.libPick=''; $S.libPickPid=0 } }
function InRoots($fp){ if(-not $fp){ return $false }; foreach($r in (DlRoots)){ try{ $rr=[IO.Path]::GetFullPath($r).TrimEnd('\','/'); $ff=[IO.Path]::GetFullPath($fp); if($ff.StartsWith($rr+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){ return $true } }catch{} }; return $false }
$wvScript=@'
@@INCLUDE:src/ui/wv-window.ps1@@
'@
function Find-Browser{
 if($env:YTDL_BROWSER){ return $env:YTDL_BROWSER }
 if(-not $WIN){ return $null }
 foreach($rel in @('Microsoft\Edge\Application\msedge.exe','Google\Chrome\Application\chrome.exe')){
  foreach($root in @($env:ProgramFiles,${env:ProgramFiles(x86)},$env:LocalAppData)){ if($root){ $c=[IO.Path]::Combine($root,$rel); if(Test-Path $c){ return $c } } } }
 return $null }
function Open-Ui($port){
 $url="http://127.0.0.1:$port/"; $s=ReadSettings; $app=$true
 if($s -and $s.openMode -eq 'browser'){ $app=$false }
 if($app -and $WIN -and -not $TEST){
  try{ $sp=[IO.Path]::Combine($bin,'wvwin.ps1'); [IO.File]::WriteAllText($sp,$wvScript,(New-Object Text.UTF8Encoding($true)))
   Start-Process powershell.exe -ArgumentList @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$sp`"","`"$url`"","`"$bin`"") ; return }catch{} }
 if($app){ $b=Find-Browser
  if($b){ try{ $prof=[IO.Path]::Combine($bin,'appwin'); $q=$(if($WIN){ '"' }else{ '' })
   Start-Process $b -ArgumentList @("--app=$url",'--window-size=1040,940','--no-first-run',"--user-data-dir=$q$prof$q"); return }catch{} } }
 if($WIN -and -not $TEST){ Start-Process $url } }
function Open-Folder($p){ if($TEST){ return }; if($WIN){ Start-Process explorer.exe "`"$p`"" } }
