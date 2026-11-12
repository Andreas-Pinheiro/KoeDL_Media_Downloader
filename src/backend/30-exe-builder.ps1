# ------------------------------------------------------------------ gerar o .exe (so quando rodando como .bat/.ps1)
$cs=@'
@@INCLUDE:src/backend/csharp/App.WebView2.cs@@
'@
$csBasic=@'
@@INCLUDE:src/backend/csharp/App.Basic.cs@@
'@
$setupCs=@'
@@INCLUDE:src/backend/csharp/Setup.cs@@
'@
$wv2Sb={ param($S,$lib)
 . ([scriptblock]::Create($lib))
 $d=J $S.bin 'wv2'; $tmpz=''; $x=''
 try{
  New-Item -ItemType Directory -Force $d | Out-Null
  $ok=J $d 'ok.txt'; $fail=J $d 'fail.txt'
  $have=(Test-Path (J $d 'Microsoft.Web.WebView2.WinForms.dll')) -and (Test-Path (J $d 'Microsoft.Web.WebView2.Core.dll')) -and (Test-Path $ok)
  if($have -and ((Get-Date)-(Get-Item $ok).LastWriteTime).TotalDays -lt 7){ return }
  $idxUrl=$(if($env:YTDL_NUGET_INDEX){ $env:YTDL_NUGET_INDEX }else{ 'https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/index.json' })
  $ver=''
  try{ $idx=Invoke-RestMethod $idxUrl -TimeoutSec 30; $vs=@($idx.versions|Where-Object{ $_ -match '^\d+(\.\d+){3}$' }|Sort-Object { [version]$_ }); if($vs.Count){ $ver="$($vs[-1])" } }catch{ L (Tr "(webview2: nao consegui consultar a ultima versao: $($_.Exception.Message))" "(webview2: could not check the latest version: $($_.Exception.Message))") }
  if(-not $ver){ $ver='1.0.2739.15' }
  $cur=''; if(Test-Path $ok){ $cur=(Get-Content $ok -Raw).Trim() }
  if($have -and $cur -eq $ver){ Set-Content $ok $ver; return }
  $pk=$(if($env:YTDL_NUGET_PKG){ $env:YTDL_NUGET_PKG }else{ "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/$ver/microsoft.web.webview2.$ver.nupkg" })
  $tmpz=J ([IO.Path]::GetTempPath()) ('wv2_'+[guid]::NewGuid().ToString('N')+'.zip'); $x="$tmpz.d"
  L (Tr "webview2: baixando o componente da janela ($ver)..." "webview2: downloading the window component ($ver)...")
  if(-not(GetFile $pk $tmpz)){ if(-not $have){ Set-Content $fail (Get-Date -Format s) }; return }
  Expand-Archive $tmpz $x -Force
  foreach($f in 'Microsoft.Web.WebView2.Core.dll','Microsoft.Web.WebView2.WinForms.dll'){ $src=J $x 'lib' 'net462' $f; if(Test-Path $src){ try{ Copy-Item $src (J $d $f) -Force }catch{ L "(webview2: $($_.Exception.Message))" } } }
  foreach($a in 'x64','x86'){ $src=J $x 'runtimes' "win-$a" 'native' 'WebView2Loader.dll'; if(Test-Path $src){ New-Item -ItemType Directory -Force (J $d $a) | Out-Null; try{ Copy-Item $src (J $d $a 'WebView2Loader.dll') -Force }catch{} } }
  if((Test-Path (J $d 'Microsoft.Web.WebView2.WinForms.dll')) -and (Test-Path (J $d 'Microsoft.Web.WebView2.Core.dll'))){ Set-Content $ok $ver; Remove-Item $fail -ea 0; L (Tr "webview2: pronto ($ver)." "webview2: ready ($ver).") }
  elseif(-not $have){ Set-Content $fail (Get-Date -Format s); L (Tr '(webview2: o pacote nao tinha os arquivos esperados)' '(webview2: the package did not have the expected files)') }
 }catch{ L "(webview2: $($_.Exception.Message))"; if(-not $have){ try{ Set-Content (J $d 'fail.txt') (Get-Date -Format s) }catch{} } }
 finally{ if($tmpz){ Remove-Item $tmpz,$x -Recurse -Force -ea 0 } }
}
$schedSb={ param($S,$lib,$prepText)
 $sb=[scriptblock]::Create($prepText)
 while($true){ Start-Sleep -Seconds 21600; if(-not $S.running -and $S.ready){ try{ & $sb $S $lib $false }catch{} } } }
$icoB64=@'
@@B64:assets/app.ico@@
'@
$logoB64=@'
@@B64:assets/logo-window.png@@
'@
$exeSb={ param($S,$lib,$cs,$csBasic,$setupCs)
 . ([scriptblock]::Create($lib))
 try{
  $dir=$S.dir; $exe=J $dir 'KoeDL.exe'; $stamp=J $S.bin 'exe.stamp'
  $hash=Md5 ($S.payload+$cs+$csBasic+$setupCs); $setupExe=J $dir 'KoeDL-Setup.exe'
  if((Test-Path $exe) -and (Test-Path $stamp) -and ((Get-Content $stamp -Raw).Trim() -eq $hash)){ $S.exeok=$true; if(-not(Test-Path $setupExe)){ try{ Copy-Item $exe $setupExe -Force }catch{} }; [void](Make-Shortcuts $true); return }
  $tmp=J ([IO.Path]::GetTempPath()) ('ytb_'+[guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force $tmp | Out-Null
  $pf=J $tmp 'payload.ps1'; [IO.File]::WriteAllText($pf,$S.payload,(New-Object Text.UTF8Encoding $false))
  $ico=J $tmp 'app.ico'; [IO.File]::WriteAllBytes($ico,[Convert]::FromBase64String($S.icoB64))
  $lg=J $tmp 'logo.png'; [IO.File]::WriteAllBytes($lg,[Convert]::FromBase64String($S.logoB64))
  $prov=New-Object Microsoft.CSharp.CSharpCodeProvider
  $out=J $tmp 'out.exe'; $built=$false; $tier=0
  foreach($src in @($cs,$csBasic)){ $tier++
   $cp=New-Object CodeDom.Compiler.CompilerParameters
   $cp.GenerateExecutable=$true; $cp.OutputAssembly=$out
   $cp.CompilerOptions='/target:winexe /optimize /win32icon:"'+$ico+'"'
   foreach($r in 'System.dll','System.Windows.Forms.dll','System.Drawing.dll'){ [void]$cp.ReferencedAssemblies.Add($r) }
   [void]$cp.EmbeddedResources.Add($pf); [void]$cp.EmbeddedResources.Add($lg)
   $res=$prov.CompileAssemblyFromSource($cp,[string[]]@($src,$setupCs))
   if(-not $res.Errors.HasErrors){ $built=$true; if($tier -eq 2){ L (Tr '(.exe gerado sem a janela WebView2: o codigo dela nao compilou neste Windows; usando Edge/Chrome)' '(.exe built without the WebView2 window: its code did not compile on this Windows; using Edge/Chrome)') }; break }
   $k=0; foreach($e in $res.Errors){ if($k -lt 3){ L "(exe tier $tier) $e" }; $k++ } }
  if(-not $built){ return }
  try{ Copy-Item $out $exe -Force; try{ Copy-Item $out $setupExe -Force }catch{}; Set-Content $stamp $hash; $S.exeok=$true; L (Tr "Gerei/atualizei o KoeDL.exe ao lado deste arquivo." "Created/updated KoeDL.exe next to this file."); [void](Make-Shortcuts $true) }
  catch{ L (Tr "(exe em uso - sera atualizado na proxima vez que o programa abrir sem o .exe rodando)" "(exe in use - it will be updated next time the program opens without the .exe running)") }
  Remove-Item $tmp -Recurse -Force -ea 0
 }catch{ L (Tr "(nao consegui gerar o .exe: $($_.Exception.Message))" "(could not build the .exe: $($_.Exception.Message))") }
}

