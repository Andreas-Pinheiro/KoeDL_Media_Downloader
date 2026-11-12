function Bg($sb,$a){ $rsp=[runspacefactory]::CreateRunspace(); $rsp.Open(); $p=[powershell]::Create(); $p.Runspace=$rsp
 [void]$p.AddScript($sb.ToString()); foreach($x in $a){ [void]$p.AddArgument($x) }; [void]$p.BeginInvoke() }
function ReadSettings{ if(Test-Path $settingsFile){ try{ return (Get-Content $settingsFile -Raw -Encoding UTF8|ConvertFrom-Json) }catch{} }; return $null }
function GetDl{ $s=ReadSettings; $d=$null; if($s -and $s.dlDir){ $d="$($s.dlDir)".Trim() }
 if(-not $d){ $d=$(if($env:YTDL_INSTALLED){ $(if((-not(Test-Path ([IO.Path]::Combine($env:USERPROFILE,'Downloads','KoeDL')))) -and (Test-Path ([IO.Path]::Combine($env:USERPROFILE,'Downloads','Media Downloader')))){ [IO.Path]::Combine($env:USERPROFILE,'Downloads','Media Downloader') }else{ [IO.Path]::Combine($env:USERPROFILE,'Downloads','KoeDL') }) }else{ [IO.Path]::Combine($dir,'Downloads') }) }
 try{ New-Item -ItemType Directory -Force $d | Out-Null }catch{ $d=[IO.Path]::Combine($dir,'Downloads'); New-Item -ItemType Directory -Force $d | Out-Null }
 return $d }
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
