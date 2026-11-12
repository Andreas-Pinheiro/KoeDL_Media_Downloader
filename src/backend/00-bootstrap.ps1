###PS###
$ErrorActionPreference='Continue'
try{ [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12 }catch{}
try{ [Console]::OutputEncoding=[Text.Encoding]::UTF8 }catch{}
$WIN = -not ($IsLinux -or $IsMacOS)
$TEST = [bool]$env:YTDL_TEST
$self=$env:SELF
$dir=$(if($env:YTDL_DIR){ $env:YTDL_DIR }else{ Split-Path $self })
$bin=[IO.Path]::Combine($dir,'bin'); $arc=[IO.Path]::Combine($bin,'archives')
New-Item -ItemType Directory -Force $bin,$arc | Out-Null
$sep=[IO.Path]::PathSeparator
$env:PATH="$bin$sep$env:PATH"; $env:PYTHONUTF8='1'
$yt=$(if($env:YTDL_BIN){ $env:YTDL_BIN }elseif($WIN){ [IO.Path]::Combine($bin,'yt-dlp.exe') }else{ [IO.Path]::Combine($bin,'yt-dlp') })
$settingsFile=[IO.Path]::Combine($bin,'settings.json')
$APPVER='@@VERSION@@'
$updFile=[IO.Path]::Combine($bin,'app.update.ps1')
if(-not $env:YTDL_OVR -and (Test-Path $updFile)){
 try{ $tx=[IO.File]::ReadAllText($updFile,[Text.Encoding]::UTF8); $mm=[regex]::Match($tx,'APPVER=.([0-9.]+).')
  if($mm.Success -and ([version]$mm.Groups[1].Value) -gt ([version]$APPVER)){ $env:YTDL_OVR='1'; Write-Host "Running updated version $($mm.Groups[1].Value)"; & ([scriptblock]::Create($tx)); return }
  else{ Remove-Item $updFile -ea 0 } }
 catch{ Write-Host "Ignoring a broken update file: $($_.Exception.Message)"; Remove-Item $updFile -ea 0 } }

# ------------------------------------------------------------------ estado compartilhado
$S=[hashtable]::Synchronized(@{running=$false;status='Idle';lang='en';pct=0;speed='';eta='';item='';cur='';browser='';done=0;total=0;pid=0;lpid=0;ipid=0;stop=$false;
 ready=$false;lastErr='';note='';selfUpd=$true;appver=$APPVER;self=$self;prep='Starting...';ver=@{};win=$WIN;test=$TEST;yt=$yt;bin=$bin;dir=$dir;rc=$false;jsr=$false;payload='';exeok=$false;chk='';logoB64='';
 info=@{busy=$false};lastBrowser=-1})
$S.files=[Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
$S.log=[Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
$S.fails=[Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
$S.alts=[Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
$PL=[hashtable]::Synchronized(@{busy=$false;title='';err='';stop=$false})
$PL.items=[Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))

