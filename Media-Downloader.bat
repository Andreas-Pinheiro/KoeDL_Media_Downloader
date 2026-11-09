@echo off
rem Media Downloader - by Bibinho1999 - github.com/Bibinho1999/Media-Downloader
chcp 65001 >nul
title Media Downloader - nao feche esta janela
set "SELF=%~f0"
powershell -NoProfile -Command "$f=[IO.File]::ReadAllText($env:SELF,[Text.Encoding]::UTF8);$c=$f.Substring($f.LastIndexOf('###'+'PS###')+8);& ([scriptblock]::Create($c))"
echo.
echo Encerrado. Pressione uma tecla para fechar.
pause >nul
exit /b
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
$APPVER='2.1'
$updFile=[IO.Path]::Combine($bin,'app.update.ps1')
if(-not $env:YTDL_OVR -and (Test-Path $updFile)){
 try{ $tx=[IO.File]::ReadAllText($updFile,[Text.Encoding]::UTF8); $mm=[regex]::Match($tx,'APPVER=.([0-9.]+).')
  if($mm.Success -and ([version]$mm.Groups[1].Value) -gt ([version]$APPVER)){ $env:YTDL_OVR='1'; Write-Host "Running updated version $($mm.Groups[1].Value)"; & ([scriptblock]::Create($tx)); return }
  else{ Remove-Item $updFile -ea 0 } }
 catch{ Write-Host "Ignoring a broken update file: $($_.Exception.Message)"; Remove-Item $updFile -ea 0 } }

# ------------------------------------------------------------------ estado compartilhado
$S=[hashtable]::Synchronized(@{running=$false;status='Idle';lang='en';pct=0;speed='';eta='';item='';cur='';browser='';done=0;total=0;pid=0;lpid=0;ipid=0;stop=$false;
 ready=$false;lastErr='';note='';selfUpd=$true;appver=$APPVER;self=$self;prep='Starting...';ver=@{};win=$WIN;test=$TEST;yt=$yt;bin=$bin;dir=$dir;rc=$false;jsr=$false;payload='';exeok=$false;
 info=@{busy=$false};lastBrowser=-1})
$S.log=[Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
$S.fails=[Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
$S.alts=[Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
$PL=[hashtable]::Synchronized(@{busy=$false;title='';err='';stop=$false})
$PL.items=[Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))

# ------------------------------------------------------------------ funcoes comuns (reusadas nos runspaces)
$lib=@'
function J{ [IO.Path]::Combine([string[]]$args) }
function Tr($pt,$en){ if($S.lang -eq 'pt'){ return $pt }else{ return $en } }
function L($m){ [void]$S.log.Add([string]$m); if($S.log.Count -gt 600){ $S.log.RemoveRange(0,100) } }
function IntOf($v){ $i=0; if([int]::TryParse("$v",[ref]$i)){ return $i } ; return 0 }
function Sanit($s){ $r=(("$s" -replace '[\\/:*?"<>|]','_') -replace '%','%%').Trim().TrimEnd('.'); if(-not $r){ $r='Playlist' }; return $r }
function Md5($t){ ([BitConverter]::ToString([Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($t))) -replace '-','') }
function Cfg($a){
 $p=J ([IO.Path]::GetTempPath()) ('ytcfg_'+[guid]::NewGuid().ToString('N')+'.txt')
 $t='# coding: utf-8'+"`n"+(($a|ForEach-Object{ '"'+((([string]$_) -replace '\\','/') -replace '"','\"')+'"' }) -join "`n")
 [IO.File]::WriteAllText($p,$t,(New-Object Text.UTF8Encoding $false)); return $p }
function KillTree($id){ if(-not $id){ return }
 if($S.win){ & taskkill /PID $id /T /F *>$null } else { try{ & pkill -P $id *>$null; & kill $id *>$null }catch{} } }
function Spawn($cfg,$key){
 $psi=New-Object Diagnostics.ProcessStartInfo
 if($S.win){ $psi.FileName=$env:ComSpec; $psi.Arguments='/c "chcp 65001>nul & "'+$S.yt+'" --ignore-config --config-locations "'+$cfg+'" 2>&1"' }
 else{ $psi.FileName='/bin/sh'; [void]$psi.ArgumentList.Add('-c'); [void]$psi.ArgumentList.Add('"'+$S.yt+'" --ignore-config --config-locations "'+$cfg+'" 2>&1') }
 $psi.UseShellExecute=$false; $psi.RedirectStandardOutput=$true; $psi.CreateNoWindow=$true; $psi.StandardOutputEncoding=[Text.Encoding]::UTF8
 $p=[Diagnostics.Process]::Start($psi); $S[$key]=$p.Id; return $p }
function Cap($a,$key){ $cfg=Cfg $a; $p=Spawn $cfg $key; $t=$p.StandardOutput.ReadToEnd(); $p.WaitForExit(); $S[$key]=0; Remove-Item $cfg -ea 0; return ($t -split "`r?`n") }
function Why($m){ switch -regex ($m){
  'country|geo' {return (Tr 'Bloqueado no seu pais (tente VPN)' 'Blocked in your country (try a VPN)')}
  'claimed|copyright|UMG|SME|WMG|Sony|Warner' {return (Tr 'Bloqueado por direitos autorais' 'Blocked for copyright')}
  'terminated' {return (Tr 'Canal encerrado' 'Channel terminated')}
  'Private video|is private|private' {return (Tr 'Video privado' 'Private video')}
  'removed by the uploader|has been removed|was deleted' {return (Tr 'Removido pelo autor' 'Removed by the uploader')}
  'confirm your age|age-restricted|\bage\b' {return (Tr 'Restrito por idade (use cookies de conta logada)' 'Age-restricted (use cookies from a logged-in account)')}
  'members|Join this channel' {return (Tr 'Exclusivo para membros' 'Members only')}
  'live event|premiere|will begin' {return (Tr 'Live/estreia ainda indisponivel' 'Live/premiere not available yet')}
  'DRM' {return (Tr 'Protegido por DRM (nao e possivel baixar)' 'DRM-protected (cannot be downloaded)')}
  'Unsupported URL' {return (Tr 'Link/site nao suportado' 'Unsupported link/site')}
  'HTTP Error 404|not found|Not Found' {return (Tr 'Nao encontrado (404)' 'Not found (404)')}
  'HTTP Error 403|Forbidden' {return (Tr 'Acesso negado (403)' 'Access denied (403)')}
  '[Ll]ogin|[Ss]ign in|authenticat' {return (Tr 'Exige login (marque um navegador com a conta logada)' 'Login required (tick a browser with a logged-in account)')}
  'unavailable|not available' {return (Tr 'Indisponivel' 'Unavailable')}
  default {return $m} } }
function UpdYt{ $ch=$S.chan; if(-not $ch){ $ch='stable' }
 L (Tr "Atualizando yt-dlp ($ch)..." "Updating yt-dlp ($ch)...")
 try{ foreach($x in (& $S.yt --update-to $ch 2>&1)){ L "$x" } }catch{ L (Tr "(falha ao atualizar: $($_.Exception.Message))" "(update failed: $($_.Exception.Message))") } }
function Make-Shortcuts($only){
 if(-not $S.win){ return (Tr 'So funciona no Windows.' 'Windows only.') }
 $exe=J $S.dir 'Media-Downloader.exe'; $target=$S.self; if(Test-Path $exe){ $target=$exe }
 $icon=''; try{ $f=J $S.bin 'app.ico'; [IO.File]::WriteAllBytes($f,[Convert]::FromBase64String($S.icoB64)); $icon="$f,0" }catch{}
 $ws=New-Object -ComObject WScript.Shell; $made=@()
 foreach($loc in @([Environment]::GetFolderPath('Desktop'),[Environment]::GetFolderPath('Programs'))){
  $p=J $loc 'Media Downloader.lnk'
  if($only -and -not(Test-Path $p)){ continue }
  try{ $l=$ws.CreateShortcut($p); $l.TargetPath=$target; $l.WorkingDirectory=$S.dir; if($icon){ $l.IconLocation=$icon }; $l.Save(); $made+=$loc }catch{} }
 if($made.Count){ return ((Tr 'Atalhos criados/atualizados em:' 'Shortcuts created/updated in:')+"`n"+($made -join "`n")) }
 return (Tr 'Nao consegui criar os atalhos.' 'Could not create the shortcuts.') }
function SelfUpdate($force){
 if(-not $S.selfUpd -and -not $force){ return }
 try{ $ProgressPreference='SilentlyContinue'
  $u=$(if($env:YTDL_UPDURL){ $env:YTDL_UPDURL }else{ 'https://raw.githubusercontent.com/Bibinho1999/Media-Downloader/main/Media-Downloader.bat' })
  $r=Invoke-WebRequest $u -UseBasicParsing -TimeoutSec 40
  $txt=[Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
  $m=[regex]::Match($txt,'APPVER=.([0-9.]+).'); $ix=$txt.LastIndexOf('###'+'PS###')
  if($m.Success -and $ix -ge 0 -and ([version]$m.Groups[1].Value) -gt ([version]$S.appver)){
   $pl=$txt.Substring($ix+8); $t=$null; $e=$null; [void][Management.Automation.Language.Parser]::ParseInput($pl,[ref]$t,[ref]$e)
   if($e.Count -eq 0){ [IO.File]::WriteAllText((J $S.bin 'app.update.ps1'),$pl,(New-Object Text.UTF8Encoding $false))
    $S.note=(Tr "Baixei a versao $($m.Groups[1].Value) do programa. Feche e abra de novo para usar." "Downloaded program version $($m.Groups[1].Value). Close and reopen to use it.")
    L $S.note }
   else{ L (Tr '(atualizacao do programa ignorada: arquivo invalido)' '(program update ignored: invalid file)') } }
  elseif($force){ L (Tr 'O programa ja esta na versao mais recente.' 'The program is already up to date.') }
 }catch{ L (Tr "(nao consegui verificar atualizacoes do programa: $($_.Exception.Message))" "(could not check for program updates: $($_.Exception.Message))") } }
function Run($u,$c,$base,$o,$fl){
 $cfg=Cfg ($base+$c+@($u))
 $p=Spawn $cfg 'pid'; $S.status=(Tr 'Baixando' 'Downloading')
 $bot=0; $fatal=$false; $n=0; $stale=$false
 while(($ln=$p.StandardOutput.ReadLine()) -ne $null){
  if($ln -match '^YTLP\|([^|]*)\|([^|]*)\|(.*)$'){
   $pc=($matches[1] -replace '[^\d.]',''); if($pc){ try{ $S.pct=[double]::Parse($pc,[Globalization.CultureInfo]::InvariantCulture) }catch{} }
   $sp=$matches[2].Trim(); if($sp -and $sp -ne 'NA' -and $sp -ne 'Unknown'){ $S.speed=$sp }
   $et=$matches[3].Trim(); if($et -and $et -ne 'NA' -and $et -ne 'Unknown'){ $S.eta=$et }
   continue }
  if($ln -match '^\[download\]\s+[\d.]+%'){ continue }
  if($ln -match '^YTLOK:\s*"?(.+?)"?\s*$'){ $S.cur=Split-Path $matches[1] -Leaf; $n++; L ('[ok] '+$S.cur); continue }
  L $ln
  if($ln -match 'Downloading item (\d+) of (\d+)'){ if(-not $S.fixedItem){ $S.item="$($matches[1])/$($matches[2])" }; $S.pct=0 }
  if($ln -match '(Destination|Merging formats into):?\s+"?(.+?)"?$'){ $S.cur=Split-Path $matches[2] -Leaf }
  if($ln -match 'has already been (downloaded|recorded)'){ $n++ }
  if($ln -match 'ERROR'){
   if($ln -match 'Unable to extract|nsig extraction failed|Failed to extract'){ $stale=$true }
   if($ln -match 'Sign in to confirm|not a bot|HTTP Error 429|Too Many Requests|rate-limited|rate-limit|cookies are no longer valid|Please sign in|[Ll]ogin required|requires? (login|authentication)|[Yy]ou need to log in|Use --cookies|cookies .* for the authentication'){ $bot++ }
   elseif($ln -match 'Could not copy|Failed to decrypt|cookie database|cookies database|DPAPI|database is locked|could not find .* cookies|Permission denied.*[Cc]ookies'){ $fatal=$true; L (Tr '(dica: feche o navegador ou use outro; o Firefox e o mais estavel)' '(tip: close the browser or use another one; Firefox is the most stable)') }
   elseif($ln -match 'ERROR: \[([^\]]+)\] ([^:\s]+): (.*)'){
    $ex=$matches[1]; $id=$matches[2]; $msg=$matches[3]
    if($ex -match '^youtube' -and $id -match '^[\w-]{11}$'){ [void]$fl.Add(@{id=$id;msg=$msg}) }
    else{ [void]$S.fails.Add("[$ex] $id - $(Why $msg)") } }
   else{ [void]$S.fails.Add($ln) }
  }
  if($bot -ge 2 -or $fatal){ KillTree $p.Id; break }
 }
 $p.WaitForExit(); $S['pid']=0; Remove-Item $cfg -ea 0
 $blocked=($bot -ge 2) -or ($bot -ge 1 -and $n -eq 0)
 return [pscustomobject]@{fatal=$fatal;bot=$bot;n=$n;stale=$stale;blocked=$blocked} }
function GetFile($urls,$out){ $ProgressPreference='SilentlyContinue'
 try{ [Net.WebRequest]::DefaultWebProxy.Credentials=[Net.CredentialCache]::DefaultCredentials }catch{}
 $curl=$null; if($S.win){ $c=Get-Command curl.exe -ea 0; if($c){ $curl=$c.Source } }
 foreach($url in @($urls)){ $nm=($url -split '/')[-1]
  $wait=@(2,5,10,20)
  for($i=1;$i -le 4;$i++){
   $t="$out.part"; Remove-Item $t -ea 0
   try{
    if($curl -and ($i % 2 -eq 0)){ & $curl -L --fail --silent --show-error --connect-timeout 30 --max-time 900 -o $t $url 2>&1 | ForEach-Object{ $S.lastErr="$_" }; if($LASTEXITCODE -ne 0 -or -not(Test-Path $t)){ throw (Tr "curl falhou ($LASTEXITCODE) $($S.lastErr)" "curl failed ($LASTEXITCODE) $($S.lastErr)") } }
    else{ Invoke-WebRequest $url -OutFile $t -UseBasicParsing -TimeoutSec 900 }
    Move-Item $t $out -Force; return $true }
   catch{ $S.lastErr=$_.Exception.Message; L (Tr "  falha ao baixar $nm ($i/4): $($_.Exception.Message)" "  failed to download $nm ($i/4): $($_.Exception.Message)"); Remove-Item $t -ea 0; if($i -lt 4){ Start-Sleep $wait[$i-1] } } }
  L (Tr "  (tentando endereco alternativo...)" "  (trying alternative address...)") }
 return $false }
function GetZip($urls,$pat){ $z=J ([IO.Path]::GetTempPath()) ('dl_'+[guid]::NewGuid().ToString('N')+'.zip'); $x="$z.d"
 if(GetFile $urls $z){ try{ Expand-Archive $z $x -Force; Get-ChildItem $x -Recurse -Include $pat | Copy-Item -Destination $S.bin -Force }catch{ L (Tr "falha ao extrair: $($_.Exception.Message)" "failed to extract: $($_.Exception.Message)") } }
 Remove-Item $z,$x -Recurse -Force -ea 0 }
'@

. ([scriptblock]::Create($lib))

# ------------------------------------------------------------------ preparo de dependencias
$prepSb={ param($S,$lib,$force)
 . ([scriptblock]::Create($lib))
 $bin=$S.bin; $yt=$S.yt
 function Jget($u){ try{ return (Invoke-RestMethod $u -TimeoutSec 30 -Headers @{'User-Agent'='MediaDownloader';'Accept'='application/vnd.github+json'}) }catch{ $S.lastErr=$_.Exception.Message; return $null } }
 function DenoVer{ $c=Get-Command deno -ea 0; if(-not $c){ return '' }; try{ $l=(& deno --version 2>$null|Select-Object -First 1); if("$l" -match 'deno\s+(\S+)'){ return $matches[1] } }catch{}; return '?' }
 function FfVer{ $c=Get-Command ffmpeg -ea 0; if(-not $c){ return '' }; try{ $l=(& ffmpeg -version 2>$null|Select-Object -First 1); if("$l" -match 'version\s+(\S+)'){ return $matches[1] } }catch{}; return '?' }
 function VerYt{ $v=''; try{ $v="$((& $yt --version 2>$null)|Select-Object -First 1)" }catch{}; return $v }
 function Ver{ $v=VerYt; $h=''; try{ $h=(& $yt --help 2>&1|Out-String) }catch{}
  $S.rc=($h -match '--remote-components'); $S.jsr=($h -match '--js-runtimes')
  $S.ver=@{ytdlp="$v";ffmpeg=(FfVer);deno=(DenoVer)} }
 function Deps($force){
  $ext=$(if($S.win){'.exe'}else{''})
  $apiFF=$(if($env:YTDL_API_FF){ $env:YTDL_API_FF }else{ 'https://api.github.com/repos/yt-dlp/FFmpeg-Builds/releases/tags/latest' })
  $zipFF=$(if($env:YTDL_ZIP_FF){ @($env:YTDL_ZIP_FF) }else{ @('https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip','https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip') })
  $apiDn=$(if($env:YTDL_API_DENO){ $env:YTDL_API_DENO }else{ 'https://api.github.com/repos/denoland/deno/releases/latest' })
  $zipDn=$(if($env:YTDL_ZIP_DENO){ $env:YTDL_ZIP_DENO }else{ 'https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip' })
  $stampF=J $bin 'deps.stamp'
  $recent=(Test-Path $stampF) -and (((Get-Date)-(Get-Item $stampF).LastWriteTime).TotalHours -lt 3) -and -not $force
  $apiFail=$false
  # ---- ffmpeg: compara a data do build instalado com a do build mais recente
  $ffBin=J $bin "ffmpeg$ext"; $ffVerF=J $bin 'ffmpeg.ver'; $needFF=$false; $remote=''
  if(-not(Get-Command ffmpeg -ea 0)){ $needFF=$true }
  elseif((Test-Path $ffBin) -and -not $recent){
   $S.prep=(Tr 'Verificando a versao do ffmpeg...' 'Checking the ffmpeg version...')
   $rel=Jget $apiFF
   if($rel){ $as=@($rel.assets|Where-Object{ $_.name -eq 'ffmpeg-master-latest-win64-gpl.zip' }); if($as.Count){ $ua=$as[0].updated_at; if($ua -is [datetime]){ $ua=$ua.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }; $remote="$ua" } }
   $local=''; if(Test-Path $ffVerF){ $local=(Get-Content $ffVerF -Raw).Trim() }
   if($remote -and $remote -ne $local){ $needFF=$true; L (Tr "ffmpeg: ha uma versao mais nova ($remote). Atualizando..." "ffmpeg: a newer build exists ($remote). Updating...") }
   elseif($remote){ L (Tr 'ffmpeg: ja esta na versao mais recente.' 'ffmpeg: already up to date.') }
   else{ $apiFail=$true; L (Tr "(nao consegui consultar a versao mais recente do ffmpeg: $($S.lastErr); mantendo a instalada)" "(could not check the latest ffmpeg version: $($S.lastErr); keeping the installed one)") } }
  if($needFF){ $S.prep=(Tr 'Baixando/atualizando o ffmpeg (~100 MB)...' 'Downloading/updating ffmpeg (~100 MB)...')
   GetZip $zipFF @("ffmpeg$ext","ffprobe$ext")
   if(Test-Path $ffBin){ if(-not $remote){ $remote=(Get-Date -Format s) }; Set-Content $ffVerF $remote; L (Tr 'ffmpeg: instalado/atualizado.' 'ffmpeg: installed/updated.') } }
  # ---- deno: compara a versao instalada com a ultima publicada
  $dnBin=J $bin "deno$ext"
  if(-not(Get-Command deno -ea 0)){ $S.prep=(Tr 'Baixando o deno (necessario para alguns sites)...' 'Downloading deno (needed for some sites)...'); GetZip $zipDn @("deno$ext"); if(Test-Path $dnBin){ L (Tr 'deno: instalado.' 'deno: installed.') } }
  elseif((Test-Path $dnBin) -and -not $recent){
   $S.prep=(Tr 'Verificando a versao do deno...' 'Checking the deno version...')
   $rel=Jget $apiDn; $latest=''; if($rel){ $latest=("$($rel.tag_name)" -replace '^v','') }
   $cur=DenoVer
   if(-not $latest){ $apiFail=$true; L (Tr "(nao consegui consultar a versao mais recente do deno: $($S.lastErr); mantendo a instalada)" "(could not check the latest deno version: $($S.lastErr); keeping the installed one)") }
   elseif($latest -ne $cur){ L (Tr "deno: $cur -> $latest. Atualizando..." "deno: $cur -> $latest. Updating..."); $S.prep=(Tr 'Atualizando o deno...' 'Updating deno...')
    try{ & $dnBin upgrade 2>&1 | ForEach-Object{ L "$_" } }catch{}
    if((DenoVer) -ne $latest){ GetZip $zipDn @("deno$ext") }
    L (Tr "deno: agora na versao $(DenoVer)." "deno: now at version $(DenoVer).") }
   else{ L (Tr "deno: ja esta na versao mais recente ($cur)." "deno: already up to date ($cur).") } }
  if(-not $apiFail){ Set-Content $stampF (Get-Date -Format s) }
  foreach($t in 'ffmpeg','deno'){ if(-not(Get-Command $t -ea 0)){ L (Tr "AVISO: $t nao instalado (o download falhou). Alguns formatos/videos podem falhar. Clique em Configuracoes > Atualizar tudo para tentar de novo." "WARNING: $t is not installed (the download failed). Some formats/videos may fail. Click Settings > Update everything to try again.") } } }
 try{
  $S.ready=$false; $S.prep=(Tr 'Verificando dependencias...' 'Checking dependencies...')
  if($S.test){ if($env:YTDL_DEPSTEST){ $b0=VerYt; UpdYt; $b1=VerYt; if($b0 -ne $b1){ L "yt-dlp: $b0 -> $b1" }; Deps $force }; Ver; $S.prep=''; $S.ready=$true; if($env:YTDL_UPDURL){ SelfUpdate $force }; return }
  $ch=$S.chan; if(-not $ch){ $ch='stable' }
  $u1='https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe'; $u2='https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/yt-dlp.exe'; $u3='https://github.com/yt-dlp/yt-dlp-master-builds/releases/latest/download/yt-dlp.exe'
  $ytUrl=$(if($ch -eq 'nightly'){ @($u2,$u1,$u3) }else{ @($u1,$u2,$u3) })
  if(-not(Test-Path $yt)){ $got=$false
   for($rd=1;$rd -le 8 -and -not $got;$rd++){
    $S.prep=(Tr "Baixando yt-dlp... (rodada $rd/8)" "Downloading yt-dlp... (round $rd/8)")
    $got=GetFile $ytUrl $yt
    if(-not $got -and $rd -lt 8){ for($w=90;$w -gt 0;$w--){ $S.prep=(Tr "O GitHub nao respondeu (erro: $($S.lastErr)). Tentando de novo em $w s (rodada $rd/8). Pode deixar esta janela aberta." "GitHub did not respond (error: $($S.lastErr)). Retrying in $w s (round $rd/8). You can leave this window open."); Start-Sleep 1 } } }
   if(-not $got){ $S.prep=(Tr "ERRO: nao consegui baixar o yt-dlp (sem internet, GitHub fora do ar ou bloqueado por rede/antivirus/proxy). Ultimo erro: $($S.lastErr)`n`nPara tentar de novo: Configuracoes > Atualizar tudo agora. Alternativa manual: baixe yt-dlp.exe em github.com/yt-dlp/yt-dlp/releases/latest e coloque na pasta: $bin" "ERROR: could not download yt-dlp (no internet, GitHub down, or blocked by network/antivirus/proxy). Last error: $($S.lastErr)`n`nTo retry: Settings > Update everything now. Manual alternative: download yt-dlp.exe from github.com/yt-dlp/yt-dlp/releases/latest and put it in this folder: $bin"); return } }
  else{ $S.prep=(Tr 'Verificando a versao do yt-dlp...' 'Checking the yt-dlp version...'); $b0=VerYt; UpdYt; $b1=VerYt; if($b0 -ne $b1){ L (Tr "yt-dlp: atualizado $b0 -> $b1" "yt-dlp: updated $b0 -> $b1") }else{ L (Tr "yt-dlp: ja esta na versao mais recente ($b1)." "yt-dlp: already up to date ($b1).") } }
  Deps $force
  Ver; $S.prep=''; $S.ready=$true
  SelfUpdate $force
 }catch{ $m=(Tr "ERRO no preparo: $($_.Exception.Message)" "Setup ERROR: $($_.Exception.Message)"); L $m; $S.prep=$m }
}

# ------------------------------------------------------------------ gerar o .exe (so quando rodando como .bat/.ps1)
$cs=@'
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("Media Downloader")]
[assembly: AssemblyProduct("Media Downloader")]
[assembly: AssemblyCompany("Bibinho1999")]
[assembly: AssemblyCopyright("by Bibinho1999")]
[assembly: AssemblyVersion("2.1.0.0")]

namespace MediaDownloaderLauncher
{
    static class Program
    {
        static NotifyIcon tray;
        static Process ps;
        static string dir;
        static string bin;
        static string portFile;
        static string logPath;
        static StreamWriter logw;
        static bool pt;
        static volatile bool everUp;
        static volatile bool failShown;
        static readonly object logLock = new object();
        static Form wvForm;
        static volatile bool wvFailed;
        static volatile bool wvStarted;
        static bool askedInstall;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern bool SetDllDirectory(string path);

        static string Tx(string p, string e) { return pt ? p : e; }

        [STAThread]
        static void Main(string[] args)
        {
            bool created;
            Mutex mutex = new Mutex(true, "MediaDownloader_SingleInstance", out created);
            dir = Path.GetDirectoryName(Application.ExecutablePath);
            bin = Path.Combine(dir, "bin");
            Directory.CreateDirectory(bin);
            portFile = Path.Combine(bin, "port.txt");
            logPath = Path.Combine(bin, "app.log");
            try { string sj = File.ReadAllText(Path.Combine(bin, "settings.json")); pt = sj.Replace(" ", "").Contains("\"lang\":\"pt\""); } catch (Exception) { pt = false; }

            if (!created)
            {
                // Outra copia ja esta rodando: so abre a janela (se ela realmente estiver respondendo).
                OpenUi();
                return;
            }

            string script = Path.Combine(bin, "app.ps1");
            try
            {
                using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.ps1"))
                using (StreamReader r = new StreamReader(s, Encoding.UTF8))
                {
                    File.WriteAllText(script, r.ReadToEnd(), new UTF8Encoding(false));
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show(Tx("Não consegui preparar o programa:\n", "Could not prepare the program:\n") + ex.Message, "Media Downloader");
                return;
            }

            try { File.Delete(portFile); } catch (Exception) { }
            try
            {
                if (File.Exists(logPath) && new FileInfo(logPath).Length > 1000000) File.Delete(logPath);
                logw = new StreamWriter(new FileStream(logPath, FileMode.Append, FileAccess.Write, FileShare.ReadWrite), new UTF8Encoding(false));
                logw.AutoFlush = true;
                logw.WriteLine("---- " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " start ----");
            }
            catch (Exception) { logw = null; }

            ProcessStartInfo psi = new ProcessStartInfo("powershell.exe");
            psi.Arguments = "-NoProfile -Command \"& ([scriptblock]::Create([IO.File]::ReadAllText('" +
                script.Replace("'", "''") + "',[Text.Encoding]::UTF8)))\"";
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.EnvironmentVariables["SELF"] = Application.ExecutablePath;
            psi.EnvironmentVariables["YTDL_EXE"] = "1";
            try
            {
                ps = new Process();
                ps.StartInfo = psi;
                ps.OutputDataReceived += OnLine;
                ps.ErrorDataReceived += OnLine;
                ps.Start();
                ps.BeginOutputReadLine();
                ps.BeginErrorReadLine();
            }
            catch (Exception ex)
            {
                MessageBox.Show(Tx("Não consegui iniciar o PowerShell:\n", "Could not start PowerShell:\n") + ex.Message, "Media Downloader");
                return;
            }

            Application.EnableVisualStyles();
            tray = new NotifyIcon();
            try { tray.Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); }
            catch (Exception) { tray.Icon = SystemIcons.Application; }
            tray.Text = "Media Downloader - by Bibinho1999";
            ContextMenu menu = new ContextMenu();
            menu.MenuItems.Add(Tx("Abrir Media Downloader", "Open Media Downloader"), delegate { StartOpenUi(); });
            menu.MenuItems.Add(Tx("Abrir pasta de downloads", "Open downloads folder"), delegate { OpenDownloads(); });
            menu.MenuItems.Add("-");
            menu.MenuItems.Add(Tx("Sair", "Quit"), delegate { Quit(); });
            tray.ContextMenu = menu;
            tray.DoubleClick += delegate { StartOpenUi(); };
            tray.Visible = true;

            // abre a janela so depois que o servidor responder; se nao responder, mostra o motivo
            StartOpenUi();

            System.Windows.Forms.Timer t = new System.Windows.Forms.Timer();
            t.Interval = 1000;
            t.Tick += delegate
            {
                if (ps == null || ps.HasExited)
                {
                    t.Stop();
                    if (!everUp) ShowFail();
                    Quit();
                }
            };
            t.Start();

            Application.Run();
            GC.KeepAlive(mutex);
        }

        static void OnLine(object sender, DataReceivedEventArgs e)
        {
            if (e.Data == null || logw == null) return;
            lock (logLock)
            {
                try { logw.WriteLine(DateTime.Now.ToString("HH:mm:ss") + " " + e.Data); } catch (Exception) { }
            }
        }

        static void StartOpenUi()
        {
            Thread th = new Thread(OpenUi);
            th.IsBackground = true;
            th.Start();
        }

        static bool PortUp(string port)
        {
            int p;
            if (!int.TryParse(port, out p)) return false;
            try
            {
                using (TcpClient c = new TcpClient())
                {
                    IAsyncResult r = c.BeginConnect("127.0.0.1", p, null, null);
                    bool ok = r.AsyncWaitHandle.WaitOne(700);
                    if (ok && c.Connected) { c.EndConnect(r); return true; }
                }
            }
            catch (Exception) { }
            return false;
        }

        static void OpenUi()
        {
            string port = null;
            for (int i = 0; i < 80 && port == null; i++)
            {
                try
                {
                    if (File.Exists(portFile))
                    {
                        string p = File.ReadAllText(portFile).Trim();
                        if (p.Length > 0 && PortUp(p)) port = p;
                    }
                }
                catch (Exception) { }
                if (port == null)
                {
                    if (ps != null && ps.HasExited) return; // o aviso de falha vem do timer
                    Thread.Sleep(250);
                }
            }
            if (port == null) { ShowFail(); return; }
            everUp = true;
            string url = "http://127.0.0.1:" + port + "/";
            bool app = true;
            try { string sj = File.ReadAllText(Path.Combine(bin, "settings.json")); if (sj.Replace(" ", "").Contains("\"openMode\":\"browser\"")) app = false; } catch (Exception) { }
            if (app)
            {
                bool ok = false;
                try { ok = TryWebView(url); } catch (Exception ex) { Log("webview: " + ex.Message); }
                if (ok) return;
            }
            OpenEdgeOrBrowser(url, app);
        }

        static void OpenEdgeOrBrowser(string url, bool app)
        {
            if (app)
            {
                string b = FindBrowser();
                if (b != null)
                {
                    try
                    {
                        Process.Start(b, "--app=" + url + WinArgs() + " --no-first-run --user-data-dir=\"" + Path.Combine(bin, "appwin") + "\"");
                        return;
                    }
                    catch (Exception) { }
                }
            }
            try { Process.Start(url); } catch (Exception) { }
        }

        static void Log(string m)
        {
            if (logw == null) return;
            lock (logLock) { try { logw.WriteLine(DateTime.Now.ToString("HH:mm:ss") + " [launcher] " + m); } catch (Exception) { } }
        }

        // ---------------- WebView2 (janela propria, sem navegador) ----------------
        static bool WvRuntimeInstalled()
        {
            string[] keys = {
                @"SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}",
                @"SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" };
            RegistryKey[] hives = { Registry.LocalMachine, Registry.CurrentUser };
            foreach (RegistryKey h in hives)
            {
                foreach (string k in keys)
                {
                    try
                    {
                        using (RegistryKey rk = h.OpenSubKey(k))
                        {
                            if (rk == null) continue;
                            string pv = rk.GetValue("pv") as string;
                            if (!string.IsNullOrEmpty(pv) && pv != "0.0.0.0") return true;
                        }
                    }
                    catch (Exception) { }
                }
            }
            return false;
        }

        static bool OfferInstallRuntime()
        {
            string declined = Path.Combine(bin, "wv2", "declined.txt");
            try
            {
                if (File.Exists(declined) && (DateTime.Now - File.GetLastWriteTime(declined)).TotalDays < 30) return false;
            }
            catch (Exception) { }
            if (askedInstall) return false;
            askedInstall = true;
            DialogResult r = MessageBox.Show(
                Tx("O Media Downloader usa o Microsoft WebView2 para mostrar a janela, mas ele não está instalado neste computador.\n\nInstalar a versão mais recente agora? É gratuito e oficial da Microsoft (o Windows pode pedir permissão).\n\nSe escolher Não, o programa abre no Edge/Chrome.",
                   "Media Downloader uses Microsoft WebView2 to show its window, but it is not installed on this computer.\n\nInstall the latest version now? It is free and official from Microsoft (Windows may ask for permission).\n\nIf you choose No, the program opens in Edge/Chrome."),
                "Media Downloader", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (r != DialogResult.Yes)
            {
                try { Directory.CreateDirectory(Path.Combine(bin, "wv2")); File.WriteAllText(declined, DateTime.Now.ToString("s")); } catch (Exception) { }
                return false;
            }
            try
            {
                string f = Path.Combine(Path.GetTempPath(), "MicrosoftEdgeWebview2Setup.exe");
                ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;
                using (WebClient w = new WebClient())
                {
                    w.DownloadFile("https://go.microsoft.com/fwlink/p/?LinkId=2124703", f);
                }
                Process p = Process.Start(f, "/silent /install");
                p.WaitForExit();
                return WvRuntimeInstalled();
            }
            catch (Exception ex)
            {
                Log("install webview2: " + ex.Message);
                MessageBox.Show(Tx("Não consegui instalar o WebView2 automaticamente. Você pode instalar manualmente em: https://developer.microsoft.com/microsoft-edge/webview2/", "Could not install WebView2 automatically. You can install it manually from: https://developer.microsoft.com/microsoft-edge/webview2/"), "Media Downloader");
                return false;
            }
        }

        static bool TryWebView(string url)
        {
            if (wvFailed) return false;
            if (wvForm != null)
            {
                try
                {
                    wvForm.BeginInvoke((MethodInvoker)delegate { wvForm.Show(); wvForm.WindowState = FormWindowState.Normal; wvForm.Activate(); });
                    return true;
                }
                catch (Exception) { }
            }
            string d = Path.Combine(bin, "wv2");
            string winforms = Path.Combine(d, "Microsoft.Web.WebView2.WinForms.dll");
            string core = Path.Combine(d, "Microsoft.Web.WebView2.Core.dll");
            for (int i = 0; i < 240; i++)
            {
                if (File.Exists(winforms) && File.Exists(core)) break;
                if (File.Exists(Path.Combine(d, "fail.txt"))) break;
                if (ps != null && ps.HasExited) break;
                Thread.Sleep(250);
            }
            if (!File.Exists(winforms) || !File.Exists(core)) { Log("webview2 files not available, using Edge/Chrome"); return false; }
            if (!WvRuntimeInstalled())
            {
                if (!OfferInstallRuntime()) return false;
                if (!WvRuntimeInstalled()) return false;
            }
            if (wvStarted) return true;
            wvStarted = true;
            Thread th = new Thread(delegate() { ShowWv(url, d, winforms, core); });
            th.SetApartmentState(ApartmentState.STA);
            th.IsBackground = true;
            th.Start();
            for (int i = 0; i < 80 && wvForm == null && !wvFailed; i++) Thread.Sleep(250);
            return wvForm != null && !wvFailed;
        }


        static bool LoadWin(out int x, out int y, out int w, out int h, out bool max)
        {
            x = y = w = h = 0; max = false;
            try
            {
                string[] a = File.ReadAllText(Path.Combine(bin, "win.txt")).Trim().Split(',');
                if (a.Length < 4) return false;
                x = int.Parse(a[0]); y = int.Parse(a[1]); w = int.Parse(a[2]); h = int.Parse(a[3]);
                max = a.Length >= 5 && a[4] == "1";
                return w >= 600 && h >= 500;
            }
            catch (Exception) { return false; }
        }

        static string WinArgs()
        {
            int x, y, w, h; bool m;
            if (LoadWin(out x, out y, out w, out h, out m)) return " --window-size=" + w + "," + h + " --window-position=" + x + "," + y;
            return " --window-size=1040,940";
        }

        static void SaveWin(Form f)
        {
            try
            {
                Rectangle b = f.WindowState == FormWindowState.Normal ? f.Bounds : f.RestoreBounds;
                File.WriteAllText(Path.Combine(bin, "win.txt"), b.X + "," + b.Y + "," + b.Width + "," + b.Height + "," + (f.WindowState == FormWindowState.Maximized ? "1" : "0"));
            }
            catch (Exception) { }
        }

        static void ShowWv(string url, string d, string winforms, string core)
        {
            try
            {
                SetDllDirectory(Path.Combine(d, Environment.Is64BitProcess ? "x64" : "x86"));
                Assembly.LoadFrom(core);
                Assembly asm = Assembly.LoadFrom(winforms);
                Type tWv = asm.GetType("Microsoft.Web.WebView2.WinForms.WebView2", true);
                Type tCp = asm.GetType("Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties", true);
                object cp = Activator.CreateInstance(tCp);
                tCp.GetProperty("UserDataFolder").SetValue(cp, Path.Combine(bin, "wv2data"), null);
                Control wv = (Control)Activator.CreateInstance(tWv);
                tWv.GetProperty("CreationProperties").SetValue(wv, cp, null);
                wv.Dock = DockStyle.Fill;

                Form f = new Form();
                f.Text = "Media Downloader";
                f.Width = 1080;
                f.Height = 980;
                f.StartPosition = FormStartPosition.CenterScreen;
                int sx, sy, sw, sh; bool smax;
                if (LoadWin(out sx, out sy, out sw, out sh, out smax))
                {
                    bool vis = false;
                    foreach (Screen sc in Screen.AllScreens) { if (sc.WorkingArea.IntersectsWith(new Rectangle(sx, sy, sw, sh))) vis = true; }
                    if (vis)
                    {
                        f.StartPosition = FormStartPosition.Manual;
                        f.SetBounds(sx, sy, sw, sh);
                        if (smax) f.WindowState = FormWindowState.Maximized;
                    }
                }
                f.ResizeEnd += delegate { SaveWin(f); };
                try { f.Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch (Exception) { }
                f.FormClosing += delegate(object s, FormClosingEventArgs e)
                {
                    SaveWin(f);
                    if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; f.Hide(); }
                };
                f.Controls.Add(wv);
                tWv.GetProperty("Source").SetValue(wv, new Uri(url), null);

                // vigia: se o WebView2 nao inicializar em 30 s, cai para o Edge/Chrome
                System.Windows.Forms.Timer wd = new System.Windows.Forms.Timer();
                wd.Interval = 1000;
                int ticks = 0;
                wd.Tick += delegate
                {
                    ticks++;
                    object core2 = null;
                    try { core2 = tWv.GetProperty("CoreWebView2").GetValue(wv, null); } catch (Exception) { }
                    if (core2 != null) { wd.Stop(); return; }
                    if (ticks >= 30)
                    {
                        wd.Stop();
                        Log("webview2 did not initialize; falling back to Edge/Chrome");
                        wvFailed = true;
                        wvForm = null;
                        OpenEdgeOrBrowser(url, true);
                        Application.ExitThread();
                    }
                };
                wd.Start();
                wvForm = f;
                Application.Run(f);
            }
            catch (Exception ex)
            {
                Log("webview2 error: " + ex.Message);
                wvFailed = true;
            }
        }

        static void ShowFail()
        {
            if (failShown) return;
            failShown = true;
            string tail = "";
            try
            {
                string[] lines;
                using (FileStream fs = new FileStream(logPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                using (StreamReader r = new StreamReader(fs, Encoding.UTF8))
                {
                    lines = r.ReadToEnd().Split('\n');
                }
                int first = Math.Max(0, lines.Length - 14);
                StringBuilder sb = new StringBuilder();
                for (int i = first; i < lines.Length; i++) sb.AppendLine(lines[i].TrimEnd('\r'));
                tail = sb.ToString();
            }
            catch (Exception) { }
            MessageBox.Show(
                Tx("O Media Downloader não conseguiu iniciar.\n\nÚltimas linhas do registro (bin\\app.log):\n\n", "Media Downloader could not start.\n\nLast lines of the log (bin\\app.log):\n\n") + tail,
                "Media Downloader");
        }

        static string FindBrowser()
        {
            string[] rels = { @"Microsoft\Edge\Application\msedge.exe", @"Google\Chrome\Application\chrome.exe" };
            string[] roots = { Environment.GetEnvironmentVariable("ProgramFiles"), Environment.GetEnvironmentVariable("ProgramFiles(x86)"), Environment.GetEnvironmentVariable("LocalAppData") };
            foreach (string rel in rels)
            {
                foreach (string root in roots)
                {
                    if (string.IsNullOrEmpty(root)) continue;
                    string c = Path.Combine(root, rel);
                    if (File.Exists(c)) return c;
                }
            }
            return null;
        }

        static void OpenDownloads()
        {
            try
            {
                string d = Path.Combine(dir, "Downloads");
                Directory.CreateDirectory(d);
                Process.Start("explorer.exe", "\"" + d + "\"");
            }
            catch (Exception) { }
        }

        static void Quit()
        {
            try
            {
                if (ps != null && !ps.HasExited)
                {
                    ProcessStartInfo k = new ProcessStartInfo("taskkill", "/PID " + ps.Id + " /T /F");
                    k.CreateNoWindow = true;
                    k.UseShellExecute = false;
                    Process.Start(k);
                }
            }
            catch (Exception) { }
            try { if (tray != null) { tray.Visible = false; tray.Dispose(); } } catch (Exception) { }
            try { File.Delete(portFile); } catch (Exception) { }
            Environment.Exit(0);
        }
    }
}
'@
$csBasic=@'
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net.Sockets;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Media Downloader")]
[assembly: AssemblyProduct("Media Downloader")]
[assembly: AssemblyCompany("Bibinho1999")]
[assembly: AssemblyCopyright("by Bibinho1999")]
[assembly: AssemblyVersion("2.1.0.0")]

namespace MediaDownloaderLauncher
{
    static class Program
    {
        static NotifyIcon tray;
        static Process ps;
        static string dir;
        static string bin;
        static string portFile;
        static string logPath;
        static StreamWriter logw;
        static bool pt;
        static volatile bool everUp;
        static volatile bool failShown;
        static readonly object logLock = new object();

        static string Tx(string p, string e) { return pt ? p : e; }

        [STAThread]
        static void Main(string[] args)
        {
            bool created;
            Mutex mutex = new Mutex(true, "MediaDownloader_SingleInstance", out created);
            dir = Path.GetDirectoryName(Application.ExecutablePath);
            bin = Path.Combine(dir, "bin");
            Directory.CreateDirectory(bin);
            portFile = Path.Combine(bin, "port.txt");
            logPath = Path.Combine(bin, "app.log");
            try { string sj = File.ReadAllText(Path.Combine(bin, "settings.json")); pt = sj.Replace(" ", "").Contains("\"lang\":\"pt\""); } catch (Exception) { pt = false; }

            if (!created)
            {
                // Outra copia ja esta rodando: so abre a janela (se ela realmente estiver respondendo).
                OpenUi();
                return;
            }

            string script = Path.Combine(bin, "app.ps1");
            try
            {
                using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.ps1"))
                using (StreamReader r = new StreamReader(s, Encoding.UTF8))
                {
                    File.WriteAllText(script, r.ReadToEnd(), new UTF8Encoding(false));
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show(Tx("Não consegui preparar o programa:\n", "Could not prepare the program:\n") + ex.Message, "Media Downloader");
                return;
            }

            try { File.Delete(portFile); } catch (Exception) { }
            try
            {
                if (File.Exists(logPath) && new FileInfo(logPath).Length > 1000000) File.Delete(logPath);
                logw = new StreamWriter(new FileStream(logPath, FileMode.Append, FileAccess.Write, FileShare.ReadWrite), new UTF8Encoding(false));
                logw.AutoFlush = true;
                logw.WriteLine("---- " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " start ----");
            }
            catch (Exception) { logw = null; }

            ProcessStartInfo psi = new ProcessStartInfo("powershell.exe");
            psi.Arguments = "-NoProfile -Command \"& ([scriptblock]::Create([IO.File]::ReadAllText('" +
                script.Replace("'", "''") + "',[Text.Encoding]::UTF8)))\"";
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.EnvironmentVariables["SELF"] = Application.ExecutablePath;
            psi.EnvironmentVariables["YTDL_EXE"] = "1";
            try
            {
                ps = new Process();
                ps.StartInfo = psi;
                ps.OutputDataReceived += OnLine;
                ps.ErrorDataReceived += OnLine;
                ps.Start();
                ps.BeginOutputReadLine();
                ps.BeginErrorReadLine();
            }
            catch (Exception ex)
            {
                MessageBox.Show(Tx("Não consegui iniciar o PowerShell:\n", "Could not start PowerShell:\n") + ex.Message, "Media Downloader");
                return;
            }

            Application.EnableVisualStyles();
            tray = new NotifyIcon();
            try { tray.Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); }
            catch (Exception) { tray.Icon = SystemIcons.Application; }
            tray.Text = "Media Downloader - by Bibinho1999";
            ContextMenu menu = new ContextMenu();
            menu.MenuItems.Add(Tx("Abrir Media Downloader", "Open Media Downloader"), delegate { StartOpenUi(); });
            menu.MenuItems.Add(Tx("Abrir pasta de downloads", "Open downloads folder"), delegate { OpenDownloads(); });
            menu.MenuItems.Add("-");
            menu.MenuItems.Add(Tx("Sair", "Quit"), delegate { Quit(); });
            tray.ContextMenu = menu;
            tray.DoubleClick += delegate { StartOpenUi(); };
            tray.Visible = true;

            // abre a janela so depois que o servidor responder; se nao responder, mostra o motivo
            StartOpenUi();

            System.Windows.Forms.Timer t = new System.Windows.Forms.Timer();
            t.Interval = 1000;
            t.Tick += delegate
            {
                if (ps == null || ps.HasExited)
                {
                    t.Stop();
                    if (!everUp) ShowFail();
                    Quit();
                }
            };
            t.Start();

            Application.Run();
            GC.KeepAlive(mutex);
        }

        static void OnLine(object sender, DataReceivedEventArgs e)
        {
            if (e.Data == null || logw == null) return;
            lock (logLock)
            {
                try { logw.WriteLine(DateTime.Now.ToString("HH:mm:ss") + " " + e.Data); } catch (Exception) { }
            }
        }

        static void StartOpenUi()
        {
            Thread th = new Thread(OpenUi);
            th.IsBackground = true;
            th.Start();
        }

        static bool PortUp(string port)
        {
            int p;
            if (!int.TryParse(port, out p)) return false;
            try
            {
                using (TcpClient c = new TcpClient())
                {
                    IAsyncResult r = c.BeginConnect("127.0.0.1", p, null, null);
                    bool ok = r.AsyncWaitHandle.WaitOne(700);
                    if (ok && c.Connected) { c.EndConnect(r); return true; }
                }
            }
            catch (Exception) { }
            return false;
        }

        static void OpenUi()
        {
            string port = null;
            for (int i = 0; i < 80 && port == null; i++)
            {
                try
                {
                    if (File.Exists(portFile))
                    {
                        string p = File.ReadAllText(portFile).Trim();
                        if (p.Length > 0 && PortUp(p)) port = p;
                    }
                }
                catch (Exception) { }
                if (port == null)
                {
                    if (ps != null && ps.HasExited) return; // o aviso de falha vem do timer
                    Thread.Sleep(250);
                }
            }
            if (port == null) { ShowFail(); return; }
            everUp = true;
            string url = "http://127.0.0.1:" + port + "/";
            bool app = true;
            try { string sj = File.ReadAllText(Path.Combine(bin, "settings.json")); if (sj.Replace(" ", "").Contains("\"openMode\":\"browser\"")) app = false; } catch (Exception) { }
            if (app)
            {
                string b = FindBrowser();
                if (b != null)
                {
                    try
                    {
                        Process.Start(b, "--app=" + url + WinArgs() + " --no-first-run --user-data-dir=\"" + Path.Combine(bin, "appwin") + "\"");
                        return;
                    }
                    catch (Exception) { }
                }
            }
            try { Process.Start(url); } catch (Exception) { }
        }


        static bool LoadWin(out int x, out int y, out int w, out int h, out bool max)
        {
            x = y = w = h = 0; max = false;
            try
            {
                string[] a = File.ReadAllText(Path.Combine(bin, "win.txt")).Trim().Split(',');
                if (a.Length < 4) return false;
                x = int.Parse(a[0]); y = int.Parse(a[1]); w = int.Parse(a[2]); h = int.Parse(a[3]);
                max = a.Length >= 5 && a[4] == "1";
                return w >= 600 && h >= 500;
            }
            catch (Exception) { return false; }
        }

        static string WinArgs()
        {
            int x, y, w, h; bool m;
            if (LoadWin(out x, out y, out w, out h, out m)) return " --window-size=" + w + "," + h + " --window-position=" + x + "," + y;
            return " --window-size=1040,940";
        }

        static void ShowFail()
        {
            if (failShown) return;
            failShown = true;
            string tail = "";
            try
            {
                string[] lines;
                using (FileStream fs = new FileStream(logPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                using (StreamReader r = new StreamReader(fs, Encoding.UTF8))
                {
                    lines = r.ReadToEnd().Split('\n');
                }
                int first = Math.Max(0, lines.Length - 14);
                StringBuilder sb = new StringBuilder();
                for (int i = first; i < lines.Length; i++) sb.AppendLine(lines[i].TrimEnd('\r'));
                tail = sb.ToString();
            }
            catch (Exception) { }
            MessageBox.Show(
                Tx("O Media Downloader não conseguiu iniciar.\n\nÚltimas linhas do registro (bin\\app.log):\n\n", "Media Downloader could not start.\n\nLast lines of the log (bin\\app.log):\n\n") + tail,
                "Media Downloader");
        }

        static string FindBrowser()
        {
            string[] rels = { @"Microsoft\Edge\Application\msedge.exe", @"Google\Chrome\Application\chrome.exe" };
            string[] roots = { Environment.GetEnvironmentVariable("ProgramFiles"), Environment.GetEnvironmentVariable("ProgramFiles(x86)"), Environment.GetEnvironmentVariable("LocalAppData") };
            foreach (string rel in rels)
            {
                foreach (string root in roots)
                {
                    if (string.IsNullOrEmpty(root)) continue;
                    string c = Path.Combine(root, rel);
                    if (File.Exists(c)) return c;
                }
            }
            return null;
        }

        static void OpenDownloads()
        {
            try
            {
                string d = Path.Combine(dir, "Downloads");
                Directory.CreateDirectory(d);
                Process.Start("explorer.exe", "\"" + d + "\"");
            }
            catch (Exception) { }
        }

        static void Quit()
        {
            try
            {
                if (ps != null && !ps.HasExited)
                {
                    ProcessStartInfo k = new ProcessStartInfo("taskkill", "/PID " + ps.Id + " /T /F");
                    k.CreateNoWindow = true;
                    k.UseShellExecute = false;
                    Process.Start(k);
                }
            }
            catch (Exception) { }
            try { if (tray != null) { tray.Visible = false; tray.Dispose(); } } catch (Exception) { }
            try { File.Delete(portFile); } catch (Exception) { }
            Environment.Exit(0);
        }
    }
}
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
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
'@
$exeSb={ param($S,$lib,$cs,$csBasic)
 . ([scriptblock]::Create($lib))
 try{
  $dir=$S.dir; $exe=J $dir 'Media-Downloader.exe'; $stamp=J $S.bin 'exe.stamp'
  $hash=Md5 ($S.payload+$cs)
  if((Test-Path $exe) -and (Test-Path $stamp) -and ((Get-Content $stamp -Raw).Trim() -eq $hash)){ $S.exeok=$true; [void](Make-Shortcuts $true); return }
  $tmp=J ([IO.Path]::GetTempPath()) ('ytb_'+[guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force $tmp | Out-Null
  $pf=J $tmp 'payload.ps1'; [IO.File]::WriteAllText($pf,$S.payload,(New-Object Text.UTF8Encoding $false))
  $ico=J $tmp 'app.ico'; [IO.File]::WriteAllBytes($ico,[Convert]::FromBase64String($S.icoB64))
  $prov=New-Object Microsoft.CSharp.CSharpCodeProvider
  $out=J $tmp 'out.exe'; $built=$false; $tier=0
  foreach($src in @($cs,$csBasic)){ $tier++
   $cp=New-Object CodeDom.Compiler.CompilerParameters
   $cp.GenerateExecutable=$true; $cp.OutputAssembly=$out
   $cp.CompilerOptions='/target:winexe /optimize /win32icon:"'+$ico+'"'
   foreach($r in 'System.dll','System.Windows.Forms.dll','System.Drawing.dll'){ [void]$cp.ReferencedAssemblies.Add($r) }
   [void]$cp.EmbeddedResources.Add($pf)
   $res=$prov.CompileAssemblyFromSource($cp,$src)
   if(-not $res.Errors.HasErrors){ $built=$true; if($tier -eq 2){ L (Tr '(.exe gerado sem a janela WebView2: o codigo dela nao compilou neste Windows; usando Edge/Chrome)' '(.exe built without the WebView2 window: its code did not compile on this Windows; using Edge/Chrome)') }; break }
   $k=0; foreach($e in $res.Errors){ if($k -lt 3){ L "(exe tier $tier) $e" }; $k++ } }
  if(-not $built){ return }
  try{ Copy-Item $out $exe -Force; Set-Content $stamp $hash; $S.exeok=$true; L (Tr "Gerei/atualizei o Media-Downloader.exe ao lado deste arquivo." "Created/updated Media-Downloader.exe next to this file."); [void](Make-Shortcuts $true) }
  catch{ L (Tr "(exe em uso - sera atualizado na proxima vez que o programa abrir sem o .exe rodando)" "(exe in use - it will be updated next time the program opens without the .exe running)") }
  Remove-Item $tmp -Recurse -Force -ea 0
 }catch{ L (Tr "(nao consegui gerar o .exe: $($_.Exception.Message))" "(could not build the .exe: $($_.Exception.Message))") }
}

# ------------------------------------------------------------------ download
$worker={ param($S,$lib,$o,$dl,$arc)
 . ([scriptblock]::Create($lib))
 function Cands($o,$dir){ $c=@(); if($o.nock){ $c+=,@() }
  $ck=J $dir 'cookies.txt'; if(Test-Path $ck){ $c+=,@('--cookies',$ck) }
  foreach($b in @($o.browsers)){ if($b){ $c+=,@('--cookies-from-browser',"$b") } }
  if($c.Count -eq 0){ $c+=,@() }; return ,$c }
 function FmtArgs($kind,$o){ $a=@()
  if($kind -eq 'v'){
   $h="$($o.vq)"; $mp4=("$($o.vcont)" -ne 'mkv')
   if($mp4){ if($h -eq 'best'){ $a+=@('-S','vcodec:h264,res,acodec:m4a') }else{ $a+=@('-S',"res:$h,vcodec:h264,acodec:m4a") }; $a+=@('--merge-output-format','mp4') }
   else{ if($h -ne 'best'){ $a+=@('-S',"res:$h") }; $a+=@('--merge-output-format','mkv') }
   if($o.meta){ $a+='--embed-metadata'; if($mp4){ $a+=@('--embed-thumbnail','--convert-thumbnails','jpg') } }
  } else {
   $f="$($o.afmt)"; $q="$($o.aq)"; $a+=@('-x','--audio-format',$f,'-f','bestaudio/best')
   if(($f -in 'mp3','m4a','opus') -and $q -and -not($q -eq '0' -and $f -ne 'mp3')){ $a+=@('--audio-quality',$q) }
   if($o.meta){ $a+='--embed-metadata'; if($f -in 'mp3','m4a'){ $a+=@('--embed-thumbnail','--convert-thumbnails','jpg') } } }
  return ,$a }
 try{
  $S.running=$true; $S.stop=$false; $S.fails.Clear(); $S.alts.Clear(); $S.log.Clear(); $S.done=0; $S.pct=0; $S.item=''; $S.fixedItem=$false
  $stamp=(Get-Date).ToString('yyyy-MM-dd HH-mm')
  $FL=New-Object Collections.ArrayList
  function FolderFor($plTitle){ switch("$($o.plmode)"){ 'none'{ return '' } 'new'{ return (Sanit $plTitle)+" [$stamp]/" } default{ return (Sanit $plTitle)+'/' } } }
  $useArc=("$($o.plmode)" -ne 'new')
  $base=@('--ignore-errors','--no-colors','--newline','--windows-filenames','--trim-filenames','120','--retries','10','--fragment-retries','10','--extractor-retries','5','--concurrent-fragments','4','--no-mtime','--socket-timeout','30',
   '--progress-template','download:YTLP|%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s','--exec','echo YTLOK:{}','-P',$dl)
  if($o.safe){ $base+=@('--sleep-interval','2','--max-sleep-interval','6') }
  if($S.rc){ $base+=@('--remote-components','ejs:github') }
  if($S.jsr -and -not(Get-Command deno -ea 0) -and (Get-Command node -ea 0)){ $base+=@('--js-runtimes','node') }
  # ---- montar a lista de tarefas
  $jobs=@(); $idp=$(if($o.addId){' [%(id)s]'}else{''})
  if("$($o.mode)" -eq 'pick'){
   $maxIdx=IntOf $o.maxIdx; $w=([string]$maxIdx).Length
   $folder=FolderFor $o.plTitle; $its=@($o.items); $k=0
   foreach($it in $its){ $k++
    $sub=''; if($o.splitType){ $sub=$(if($it.type -eq 'v'){'Videos/'}else{'Musicas/'}) }
    $pre=''; if($o.num){ $pre=([string](IntOf $it.idx)).PadLeft($w,'0')+' - ' }
    $jobs+=,@{url="$($it.url)";kind="$($it.type)";label="$($it.title)";tpl=($folder+$sub+$pre+'%(title)s'+$idp+'.%(ext)s');altpre=($folder+$sub+$pre);title="$($it.title)";extra=@('--no-playlist');arcKey="$($o.plUrl)";itemLabel="$k/$($its.Count)"} }
  } else {
   $urls=@($o.urls|Where-Object{ $_ -and "$_".Trim() }); $kind=$(if($o.kind -eq 'v'){'v'}else{'a'})
   $bd=''; if($o.batch -and $urls.Count -gt 1){ $bd="Lote $stamp/" }
   $num=$(if($o.num){'%(playlist_index&{} - |)s'}else{''})
   $ex=@(); if($o.noPl){ $ex+='--no-playlist' }else{ $ex+='--yes-playlist' }
   $st=IntOf $o.st; $en=IntOf $o.en
   if($st -gt 0){ $ex+=@('--playlist-start',"$st") }; if($en -gt 0){ $ex+=@('--playlist-end',"$en") }
   foreach($u in $urls){ $jobs+=,@{url="$u";kind=$kind;label="$u";tpl='';num=$num;idp=$idp;bd=$bd;title='';extra=$ex;arcKey="$u";itemLabel=''} }
  }
  $S.total=$jobs.Count; $cands=Cands $o $S.dir; $start=0
  if($S.lastBrowser -ge 0 -and $S.lastBrowser -lt $cands.Count){ $start=$S.lastBrowser }
  foreach($j in $jobs){
   if($S.stop){ break }
   $fmt=FmtArgs $j.kind $o
   $fk=$(if($j.kind -eq 'v'){ "v|$($o.vcont)|$($o.vq)" }else{ "a|$($o.afmt)|$($o.aq)" })
   if(-not $j.tpl){
    # pasta da playlist: o yt-dlp troca '/' por outro caractere dentro de campos, entao o nome da pasta e resolvido aqui
    $fold=''; $fb=''
    if(-not $o.noPl -and "$($o.plmode)" -ne 'none'){
     $S.status=(Tr 'Lendo o link' 'Reading the link')
     $pr=@(Cap (@('--ignore-config','--no-warnings','--ignore-errors','--flat-playlist','--playlist-items','1','--socket-timeout','30','--print','%(playlist_title,playlist_id)s')+$cands[$start]+@($j.url)) 'pid')
     $pt=@($pr|Where-Object{ $_ -and $_ -notmatch '^(ERROR|WARNING|\[)' }|Select-Object -First 1)
     if($pt.Count -and "$($pt[0])".Trim() -ne 'NA'){ $fold=FolderFor "$($pt[0])" }
     elseif(-not $pt.Count){ $fb='%(playlist_title,playlist_id&{} - |)s' } }
    $j.tpl=$j.bd+$fold+$fb+$j.num+'%(title)s'+$j.idp+'.%(ext)s'
    if($fold){ L (Tr "Pasta: $($fold.TrimEnd('/'))" "Folder: $($fold.TrimEnd('/'))") } }
   $args2=$base+$fmt+@('-o',$j.tpl)+$j.extra
   if($useArc){ $ar=J $arc ((Md5 ($j.arcKey+'|'+$fk))+'.txt'); if($o.reset){ Remove-Item $ar -ea 0 }; $args2+=@('--download-archive',$ar) } else { $ar='' }
   $S.cur=''; $S.pct=0; $S.item=$j.itemLabel; $S.fixedItem=[bool]$j.itemLabel; $FL.Clear(); L "=== $($j.label)"
   $cycle=0; $fin=$false; $updated=$false; $lastC=@(); $nocookTried=$false
   while(-not $fin -and -not $S.stop){
    $anyBot=$false
    for($k=0;$k -lt $cands.Count;$k++){
     if($S.stop){ break }
     $ci=($start+$k)%$cands.Count; $c=$cands[$ci]
     $S.browser=$(if($c.Count){ Split-Path $c[1] -Leaf }else{ (Tr 'sem cookies' 'no cookies') })
     if($cands.Count -gt 1 -or $c.Count){ L ">>> Cookies: $($S.browser)" }
     $r=Run $j.url $c $args2 $o $FL
     if($r.stale -and -not $updated){ $updated=$true; L (Tr '!!! Extrator desatualizado: atualizando o yt-dlp e tentando de novo...' '!!! Outdated extractor: updating yt-dlp and trying again...'); UpdYt; $FL.Clear(); $r=Run $j.url $c $args2 $o $FL }
     if(-not $r.fatal -and -not $r.blocked){ $fin=$true; $lastC=$c; $start=$ci; $S.lastBrowser=$ci; break }
     if($r.blocked){ $anyBot=$true }
     L (Tr "!!! $($S.browser) falhou ($(if($r.fatal){'cookies ilegiveis'}else{'bloqueio/limite/login'})). Proximo..." "!!! $($S.browser) failed ($(if($r.fatal){'unreadable cookies'}else{'block/limit/login'})). Next...")
    }
    if($fin -or $S.stop){ break }
    if(-not $anyBot -and -not $nocookTried){ $nocookTried=$true; L (Tr '>>> Tentando sem cookies...' '>>> Trying without cookies...'); $S.browser=(Tr 'sem cookies' 'no cookies')
     $r=Run $j.url @() $args2 $o $FL; if(-not $r.blocked){ $fin=$true; $lastC=@(); break } }
    $cycle++
    if($o.wait -le 0 -or $cycle -ge 3 -or -not $anyBot){ L (Tr 'Todas as fontes de cookies falharam.' 'All cookie sources failed.'); [void]$S.fails.Add((Tr "BLOQUEADO (rode de novo depois, retoma de onde parou): $($j.url)" "BLOCKED (run again later, it resumes where it stopped): $($j.url)")); break }
    for($t=(IntOf $o.wait)*60; $t -gt 0 -and -not $S.stop; $t--){ $S.status=(Tr "Aguardando $([math]::Ceiling($t/60)) min p/ recomecar" "Waiting $([math]::Ceiling($t/60)) min to start over"); Start-Sleep 1 }
   }
   # ---- itens bloqueados/removidos: procurar versao alternativa
   if($fin -and -not $S.stop -and $FL.Count){
    $seen=@{}; $items=@($FL|Where-Object{ if($seen[$_.id]){$false}else{$seen[$_.id]=$true;$true} }); $FL.Clear()
    $info=@{}; $mx=0
    if($o.alt -and -not $j.title){ L (Tr 'Lendo titulos da playlist p/ buscar alternativas...' 'Reading playlist titles to look for alternatives...')
     foreach($row in (Cap (@('--ignore-errors','--no-colors','--flat-playlist','--print','%(id)s<|>%(playlist_index)s<|>%(playlist_title)s<|>%(title)s')+$lastC+@($j.url)) 'pid')){
      $q=$row -split '<\|>',4
      if($q.Count -eq 4 -and $q[0] -match '^[\w-]{11}$'){ $info[$q[0]]=@{idx=$q[1];pl=$q[2];title=$q[3]}; $ii=0; if([int]::TryParse($q[1],[ref]$ii) -and $ii -gt $mx){ $mx=$ii } } } }
    foreach($it in $items){
     if($S.stop){ break }
     $id=$it.id; $link="https://youtu.be/$id"; $why=Why $it.msg; $t=$info[$id]; $ttl="$($j.title)"; $pre=''
     if($j.title){ $pre=$j.altpre }
     elseif($t){ $ttl=$t.title
      $pre=$j.bd
      if($t.pl -and $t.pl -ne 'NA'){ $pre+=(FolderFor $t.pl); $ii=0; if($o.num -and [int]::TryParse($t.idx,[ref]$ii)){ $pre+=([string]$ii).PadLeft(([string]$mx).Length,'0')+' - ' } } }
     if($o.alt -and $ttl -and $ttl -ne 'NA' -and $ttl -notmatch '^\[(Deleted|Private) video\]$'){
      L (Tr "ALT: buscando versao alternativa de '$ttl'..." "ALT: looking for an alternative version of '$ttl'...")
      $qs=$(if($j.kind -eq 'v'){ "ytsearch5:$ttl" }else{ "ytsearch5:$ttl audio" })
      $fa=$base+$fmt+@('-o',($pre+'%(title)s.%(ext)s'),'--max-downloads','1','--match-filter',"id!=$id")
      if($useArc){ $fa+=@('--download-archive',$ar) }
      $r=Run $qs $lastC $fa $o $FL
      if($r.n -gt 0){ [void]$S.alts.Add("$ttl  <-  $link ($why)"); continue }
     }
     [void]$S.fails.Add($(if($ttl -and $ttl -ne 'NA'){"$ttl - "}else{''})+"$why - $link")
    }
    $FL.Clear()
   }
   $S.done++
  }
  $S.status=$(if($S.stop){ (Tr 'Parado pelo usuario' 'Stopped by the user') }else{ (Tr 'Concluido' 'Done') })
 }catch{ L (Tr "ERRO interno: $($_.Exception.Message)" "Internal ERROR: $($_.Exception.Message)"); $S.status=(Tr 'Erro' 'Error') }
 finally{ $S.running=$false; $S.speed=''; $S.eta=''; $S.pct=$(if($S.status -in 'Concluido','Done'){100}else{$S.pct}) }
}

# ------------------------------------------------------------------ leitura de playlist (aba "escolher faixas")
$plSb={ param($S,$PL,$lib,$url,$browsers,$nock,$dir)
 . ([scriptblock]::Create($lib))
 try{
  $PL.busy=$true; $PL.err=''; $PL.title=''; $PL.stop=$false; $PL.items.Clear()
  $cands=@(,@()); $ck=J $dir 'cookies.txt'; if(Test-Path $ck){ $cands+=,@('--cookies',$ck) }
  foreach($b in @($browsers)){ if($b){ $cands+=,@('--cookies-from-browser',"$b") } }
  $pr='YTPL<|>%(id)s<|>%(playlist_index)s<|>%(duration)s<|>%(uploader,channel)s<|>%(playlist_title)s<|>%(webpage_url,url)s<|>%(title)s'
  foreach($c in $cands){
   if($PL.stop){ break }
   $cfg=Cfg (@('--ignore-errors','--no-colors','--flat-playlist','--yes-playlist','--socket-timeout','30','--print',$pr)+$c+@($url))
   $p=Spawn $cfg 'lpid'; $bad=$false; $errs=@()
   while(($ln=$p.StandardOutput.ReadLine()) -ne $null){
    if($PL.stop){ KillTree $p.Id; break }
    if($ln.StartsWith('YTPL<|>')){
     $q=$ln -split '<\|>',8
     if($q.Count -eq 8){
      $d=''; $dv=0.0; if([double]::TryParse($q[3],[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$dv)){ $ts=[TimeSpan]::FromSeconds($dv); $d=$(if($ts.TotalHours -ge 1){ '{0}:{1:00}:{2:00}' -f [int][math]::Floor($ts.TotalHours),$ts.Minutes,$ts.Seconds }else{ '{0}:{1:00}' -f $ts.Minutes,$ts.Seconds }) }
      $up=$q[4]; if($up -eq 'NA'){ $up='' }
      $ix=IntOf $q[2]; if($ix -le 0){ $ix=$PL.items.Count+1 }
      $ti=$q[7]; $un=($ti -match '^\[(Deleted|Private) video\]$')
      if($q[5] -and $q[5] -ne 'NA' -and -not $PL.title){ $PL.title=$q[5] }
      [void]$PL.items.Add(@{idx=$ix;id=$q[1];dur=$d;uploader=$up;url=$q[6];title=$ti;unavail=$un}) }
    } elseif($ln -match 'ERROR'){ $errs+=$ln; if($ln -match 'Sign in|login|Login|cookies|429|private'){ $bad=$true } }
   }
   $p.WaitForExit(); $S['lpid']=0; Remove-Item $cfg -ea 0
   if($PL.items.Count -gt 0){ break }
   if($errs.Count){ $PL.err=($errs|Select-Object -First 1) -replace '^ERROR:\s*','' }
   if(-not $bad -and $c.Count -eq 0){ break }
  }
  if($PL.items.Count -gt 0){ $PL.err='' } elseif(-not $PL.err){ $PL.err=(Tr 'Nenhuma faixa encontrada neste link.' 'No tracks found at this link.') }
 }catch{ $PL.err=$_.Exception.Message }
 finally{ $PL.busy=$false }
}

# ------------------------------------------------------------------ verificar link
$infoSb={ param($S,$lib,$url,$browsers,$dir)
 . ([scriptblock]::Create($lib))
 try{
  $S.info=@{busy=$true}
  $txt=(Cap @('--ignore-config','--flat-playlist','--dump-single-json','--no-warnings','--ignore-errors','--socket-timeout','30',$url) 'ipid') -join "`n"
  $js=$null; try{ $js=$txt.Substring($txt.IndexOf('{'))|ConvertFrom-Json }catch{}
  if($js){ $cnt=1; if($js.entries){ $cnt=@($js.entries).Count }
   $S.info=@{busy=$false;title="$($js.title)";count=$cnt;ex="$($js.extractor_key)";error=''} }
  else{ $m=($txt -split "`n"|Where-Object{ $_ -match 'ERROR' }|Select-Object -First 1); if(-not $m){ $m=(Tr 'sem resposta' 'no response') }; $S.info=@{busy=$false;title='';count=0;ex='';error=(Why (($m -replace '^.*ERROR:\s*','')))} }
 }catch{ $S.info=@{busy=$false;title='';count=0;ex='';error=$_.Exception.Message} }
}

# ------------------------------------------------------------------ pagina
$tok=[guid]::NewGuid().ToString('N')
$html=@'
<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Media Downloader</title>
<link id="fav" rel="icon" href="">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root{--bg:#f6f7fb;--fg:#1b1f2a;--card:#ffffff;--card2:#eef0f6;--line:#d9dde8;--mu:#5d6578;--ac:#0e7490;--acfg:#fff;--ok:#15803d;--bad:#b91c1c;--warn:#fff4d6;--warnln:#e0b34a;--sh:0 1px 2px rgba(20,30,60,.06),0 4px 14px rgba(20,30,60,.05);--r:14px;--pad:16px;--gap:14px}
@media(prefers-color-scheme:dark){:root:not([data-theme]){--bg:#10131b;--fg:#e8ebf3;--card:#181c27;--card2:#212636;--line:#2c3246;--mu:#9aa3b8;--ok:#4ade80;--bad:#f87171;--warn:#3a2f10;--warnln:#8a6d1c;--sh:0 1px 2px rgba(0,0,0,.3),0 6px 18px rgba(0,0,0,.25)}}
:root[data-theme=dark]{--bg:#10131b;--fg:#e8ebf3;--card:#181c27;--card2:#212636;--line:#2c3246;--mu:#9aa3b8;--ok:#4ade80;--bad:#f87171;--warn:#3a2f10;--warnln:#8a6d1c;--sh:0 1px 2px rgba(0,0,0,.3),0 6px 18px rgba(0,0,0,.25)}
:root[data-theme=neon]{--bg:#070a14;--fg:#e6f1ff;--card:#0e1428;--card2:#161e3a;--line:#25305a;--mu:#8fa0c9;--ok:#5eead4;--bad:#fb7185;--warn:#2b2410;--warnln:#8a6d1c;--sh:0 0 0 1px #25305a,0 0 22px rgba(34,211,238,.10)}
:root[data-theme=neon] body{background:radial-gradient(1200px 500px at 10% -10%,rgba(124,58,237,.22),transparent 60%),radial-gradient(900px 500px at 100% 0,rgba(34,211,238,.16),transparent 60%),var(--bg);background-attachment:fixed}
:root[data-dens=compact]{--pad:10px;--gap:9px}
:root[data-corner=square]{--r:4px}
*{box-sizing:border-box}
html{font-size:16px}
body{margin:0;font:1rem/1.45 system-ui,-apple-system,"Segoe UI",sans-serif;background:var(--bg);color:var(--fg);padding-bottom:128px}
.wrap{max-width:900px;margin:0 auto;padding:16px}
header{display:flex;align-items:center;gap:12px;flex-wrap:wrap;margin-bottom:6px}
header img{width:44px;height:44px;border-radius:50%;box-shadow:0 0 0 2px var(--ac)}
h1{font-size:1.35rem;margin:0;line-height:1.1}.by{font-size:.75rem;color:var(--mu)}
.sp{flex:1}
.sub{color:var(--mu);font-size:.85rem;margin:2px 0 10px}
.card{background:var(--card);border:1px solid var(--line);border-radius:var(--r);box-shadow:var(--sh);padding:var(--pad);margin:var(--gap) 0}
.card h2{font-size:1rem;margin:0 0 8px;display:flex;align-items:center;gap:8px}
.n{display:inline-grid;place-items:center;width:1.5rem;height:1.5rem;border-radius:50%;background:var(--ac);color:var(--acfg);font-size:.8rem;font-weight:700}
.mu{color:var(--mu);font-size:.85rem}
textarea,select,input[type=number],input[type=text]{width:100%;background:var(--card2);color:var(--fg);border:1px solid var(--line);border-radius:calc(var(--r) - 4px);padding:9px 10px;font:inherit}
textarea{min-height:104px;resize:vertical}
select{width:100%}
:focus-visible{outline:2px solid var(--ac);outline-offset:2px}
.row{display:flex;gap:12px;flex-wrap:wrap;align-items:flex-end}.row>*{flex:1;min-width:140px}.row>.nf{flex:none;min-width:0}
.fld{display:block}.fld>span{display:block;font-size:.8rem;color:var(--mu);margin-bottom:3px}
label.chk{display:flex;gap:8px;align-items:flex-start;margin:7px 0;cursor:pointer}
label.chk input{margin-top:.3rem}
label.chk small{display:block;color:var(--mu);font-size:.8rem}
button{background:var(--ac);color:var(--acfg);border:0;border-radius:calc(var(--r) - 4px);padding:9px 16px;font:inherit;font-weight:600;cursor:pointer}
button:hover{filter:brightness(1.08)}
button.s{background:var(--card2);color:var(--fg);border:1px solid var(--line);font-weight:500}
button.big{padding:12px 26px;font-size:1.05rem}
button:disabled{opacity:.45;cursor:default;filter:none}
.tabs{display:flex;gap:6px;margin:12px 0 0;border-bottom:1px solid var(--line)}
.tabs button{background:transparent;color:var(--mu);border-radius:10px 10px 0 0;border-bottom:3px solid transparent;font-weight:600;padding:10px 14px}
.tabs button.on{color:var(--fg);border-bottom-color:var(--ac)}
.pane{display:none}.pane.on{display:block}
.seg{display:inline-flex;background:var(--card2);border:1px solid var(--line);border-radius:calc(var(--r) - 2px);padding:3px;gap:3px;flex-wrap:wrap}
.seg label{position:relative}.seg input{position:absolute;opacity:0;inset:0;cursor:pointer}
.seg span{display:block;padding:8px 16px;border-radius:calc(var(--r) - 5px);font-weight:600;color:var(--mu);white-space:nowrap}
.seg input:checked+span{background:var(--ac);color:var(--acfg)}
.seg input:focus-visible+span{outline:2px solid var(--ac);outline-offset:2px}
details{margin-top:10px}summary{cursor:pointer;color:var(--ac);font-weight:600;padding:4px 0}
details[open]>summary{margin-bottom:6px}
#banner{background:var(--warn);border:1px solid var(--warnln);border-radius:10px;padding:10px 12px;margin:10px 0;display:none;white-space:pre-wrap;font-size:.9rem}
.tw{max-height:360px;overflow:auto;border:1px solid var(--line);border-radius:10px;background:var(--card)}
table{width:100%;border-collapse:collapse;font-size:.9rem}th,td{padding:7px 8px;text-align:left;border-bottom:1px solid var(--line)}
th{position:sticky;top:0;background:var(--card2);z-index:1}tr.na{opacity:.45}td select{padding:3px 6px;width:auto}.num{text-align:right;color:var(--mu)}
pre{background:#0a0d14;color:#9ef0b4;padding:10px;border-radius:10px;height:220px;overflow:auto;font-size:.75rem;white-space:pre-wrap;margin:6px 0 0}
#fails{color:var(--bad);white-space:pre-wrap;font-size:.85rem;margin-top:8px}#alts{color:var(--ok);white-space:pre-wrap;font-size:.85rem;margin-top:8px}
progress{width:100%;height:10px;accent-color:var(--ac)}
#bar{position:fixed;left:0;right:0;bottom:0;background:var(--card);border-top:1px solid var(--line);box-shadow:0 -6px 20px rgba(0,0,0,.12);padding:10px 16px;z-index:5}
#bar .in{max-width:900px;margin:0 auto;display:flex;gap:12px;align-items:center;flex-wrap:wrap}
#bar .st{flex:1;min-width:200px}#bar .st b{display:block;font-size:.95rem;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
#cur{color:var(--mu);font-size:.8rem;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.sw{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.sw button{width:30px;height:30px;padding:0;border-radius:50%;border:2px solid var(--card);box-shadow:0 0 0 1px var(--line)}
.sw button.on{box-shadow:0 0 0 2px var(--fg)}
.sw input[type=color]{width:36px;height:30px;padding:0;border:0;background:none}
hr{border:0;border-top:1px solid var(--line);margin:12px 0}
footer{margin:20px 0 6px;text-align:center;color:var(--mu);font-size:.75rem}footer a{color:inherit}
.hide{display:none!important}
@media(max-width:560px){.row>*{min-width:100%}#bar .in{gap:8px}}
</style></head><body><div class="wrap">
<header><img id="logo" alt=""><div><h1>Media Downloader</h1><div class="by">by Bibinho1999</div></div><div class="sp"></div>
<label class="fld nf" style="min-width:0"><span data-t="lang"></span><select id="lang"><option value="en">English</option><option value="pt">Português</option></select></label>
<button class="s nf" onclick="if(confirm(t('quit_q')))api('quit',{})" data-t="quit"></button></header>
<div class="sub"><span data-t="sub"></span> <span id="ver"></span></div>
<div id="banner"></div>

<div class="tabs"><button id="t_links" class="on" onclick="tab('links')" data-t="t_links"></button><button id="t_pick" onclick="tab('pick')" data-t="t_pick"></button><button id="t_cfg" onclick="tab('cfg')" data-t="t_cfg"></button></div>

<div id="p_links" class="pane on">
<div class="card"><h2><span class="n">1</span><span data-t="s1_links"></span></h2>
<textarea id="urls" data-ph="urlsph"></textarea>
<div class="row" style="margin-top:8px;align-items:center"><button class="s nf" onclick="chk()" data-t="chk"></button><span id="ck" class="mu"></span></div></div>
</div>

<div id="p_pick" class="pane">
<div class="card"><h2><span class="n">1</span><span data-t="s1_pick"></span></h2>
<div class="row"><div style="flex:4"><input type="text" id="plurl" data-ph="plph"></div>
<button class="nf" id="plbtn" onclick="plLoad()" data-t="plload"></button><button class="s nf" onclick="api('pl/stop',{})" data-t="stop"></button></div>
<div id="plinfo" class="mu" style="margin:8px 0" data-t="plhint"></div>
<div class="row" style="align-items:center"><span class="nf"><button class="s" onclick="mark(1)" data-t="selall"></button> <button class="s" onclick="mark(0)" data-t="selnone"></button> <button class="s" onclick="mark(2)" data-t="selinv"></button></span>
<input type="text" id="plfilter" data-ph="filt" oninput="render()"></div>
<div style="margin:10px 0"><span class="mu" data-t="as"></span><br><div class="seg" style="margin-top:4px">
<label><input type="radio" name="pm" value="a" checked><span data-t="pm_a"></span></label>
<label><input type="radio" name="pm" value="v"><span data-t="pm_v"></span></label>
<label><input type="radio" name="pm" value="m"><span data-t="pm_m"></span></label></div></div>
<div class="tw"><table><thead><tr><th></th><th class="num">#</th><th data-t="th_title"></th><th data-t="th_ch"></th><th data-t="th_dur"></th><th data-t="th_type"></th></tr></thead><tbody id="tb"></tbody></table></div></div>
</div>

<div id="s2" class="card"><h2><span class="n">2</span><span data-t="s2"></span></h2>
<div id="kindbox" style="margin-bottom:10px"><div class="seg">
<label><input type="radio" name="kind" value="a" checked><span data-t="ka"></span></label>
<label><input type="radio" name="kind" value="v"><span data-t="kv"></span></label></div></div>
<div id="gA" class="row"><label class="fld"><span data-t="afmt"></span><select id="afmt"><option value="mp3" data-t="f_mp3"></option><option value="m4a" data-t="f_m4a"></option><option value="opus">Opus</option><option value="flac" data-t="f_flac"></option><option value="wav" data-t="f_wav"></option></select></label>
<label class="fld"><span data-t="aq"></span><select id="aq"><option value="0" data-t="q_best"></option><option value="320K" data-t="q_high"></option><option value="192K" data-t="q_mid"></option><option value="128K" data-t="q_low"></option></select></label></div>
<div id="gV" class="row"><label class="fld"><span data-t="vq"></span><select id="vq"><option value="best" data-t="q_best"></option><option value="1080">1080p (Full HD)</option><option value="720">720p (HD)</option><option value="480">480p</option><option value="360">360p</option></select></label>
<label class="fld"><span data-t="vcont"></span><select id="vcont"><option value="mp4" data-t="mp4o"></option><option value="mkv" data-t="mkvo"></option></select></label></div>
<div class="mu" style="margin-top:6px" data-t="qnote"></div>
<details><summary data-t="more"></summary>
<label class="fld"><span data-t="plm"></span><select id="plmode"><option value="name" data-t="plm1"></option><option value="new" data-t="plm2"></option><option value="none" data-t="plm3"></option></select></label>
<label class="chk"><input type="checkbox" id="num"><div><span data-t="num"></span></div></label>
<label class="chk" id="rowBatch"><input type="checkbox" id="batch"><div><span data-t="batch"></span></div></label>
<label class="chk" id="rowSplit"><input type="checkbox" id="splitType"><div><span data-t="split"></span></div></label>
<div id="rowRange" class="row"><label class="fld"><span data-t="from"></span><input type="number" id="st" min="0" placeholder="1"></label><label class="fld"><span data-t="to"></span><input type="number" id="en" min="0" data-ph="all"></label></div>
<label class="chk" id="rowNoPl"><input type="checkbox" id="noPl"><div><span data-t="nopl"></span></div></label>
</details></div>

<div id="p_cfg" class="pane">
<div class="card"><h2 data-t="h_look"></h2>
<div class="row"><label class="fld"><span data-t="theme"></span><select id="theme"><option value="auto" data-t="th_auto"></option><option value="light" data-t="th_light"></option><option value="dark" data-t="th_dark"></option><option value="neon" data-t="th_neon"></option></select></label>
<label class="fld"><span data-t="fsize"></span><select id="fsize"><option value="s" data-t="fs_s"></option><option value="m" data-t="fs_m"></option><option value="l" data-t="fs_l"></option><option value="xl" data-t="fs_xl"></option></select></label>
<label class="fld"><span data-t="dens"></span><select id="density"><option value="comfy" data-t="d_comfy"></option><option value="compact" data-t="d_compact"></option></select></label>
<label class="fld"><span data-t="corner"></span><select id="corner"><option value="round" data-t="c_round"></option><option value="square" data-t="c_square"></option></select></label></div>
<div style="margin-top:10px"><span class="mu" data-t="accent"></span><div class="sw" id="sw" style="margin-top:6px">
<button data-c="#0e7490" title="Cyan"></button><button data-c="#6d28d9" title="Violet"></button><button data-c="#be185d" title="Pink"></button><button data-c="#15803d" title="Green"></button><button data-c="#c2410c" title="Orange"></button><button data-c="#b91c1c" title="Red"></button>
<input type="color" id="accent" value="#0e7490" title="Custom"><button class="s" style="width:auto;height:auto;border-radius:8px;padding:6px 10px" onclick="resetLook()" data-t="reset_look"></button></div></div></div>

<div class="card"><h2 data-t="h_where"></h2>
<label class="fld"><span data-t="dldir"></span><input type="text" id="dlDir" placeholder="C:\Users\you\Music"></label>
<label class="fld" style="margin-top:10px"><span data-t="openm"></span><select id="openMode"><option value="app" data-t="openm_a"></option><option value="browser" data-t="openm_b"></option></select></label>
<div class="row" style="margin-top:10px"><button class="s nf" onclick="shortcuts()" data-t="shortc"></button><button class="s nf" onclick="api('open',{what:'bin'})" data-t="openbin"></button></div></div>

<div class="card"><h2 data-t="h_behav"></h2>
<label class="chk"><input type="checkbox" id="selfUpd" checked><div><span data-t="selfupd"></span></div></label>
<label class="chk"><input type="checkbox" id="meta" checked><div><span data-t="meta"></span></div></label>
<label class="chk"><input type="checkbox" id="safe" checked><div><span data-t="safe"></span></div></label>
<label class="chk"><input type="checkbox" id="alt" checked><div><span data-t="alt"></span></div></label>
<label class="chk"><input type="checkbox" id="addId"><div><span data-t="addid"></span></div></label>
<label class="chk"><input type="checkbox" id="reset"><div><span data-t="reset"></span></div></label></div>

<div class="card"><h2 data-t="h_acc"></h2>
<div class="mu" data-t="accnote"></div>
<div class="row" style="margin-top:8px">
<label class="chk nf"><input type="checkbox" class="br" value="firefox" checked><div>Firefox</div></label>
<label class="chk nf"><input type="checkbox" class="br" value="edge" checked><div>Edge</div></label>
<label class="chk nf"><input type="checkbox" class="br" value="chrome" checked><div>Chrome</div></label>
<label class="chk nf"><input type="checkbox" class="br" value="brave"><div>Brave</div></label>
<label class="chk nf"><input type="checkbox" class="br" value="opera"><div>Opera</div></label>
<label class="chk nf"><input type="checkbox" class="br" value="vivaldi"><div>Vivaldi</div></label></div>
<label class="chk"><input type="checkbox" id="nock"><div><span data-t="nock"></span></div></label>
<label class="fld" style="max-width:380px"><span data-t="wait"></span><input type="number" id="wait" value="15" min="0"></label>
<div class="mu" style="margin-top:6px" data-t="cknote"></div></div>

<div class="card"><h2 data-t="h_upd"></h2>
<label class="fld" style="max-width:380px"><span data-t="chan"></span><select id="chan"><option value="stable" data-t="chan_s"></option><option value="nightly" data-t="chan_n"></option></select></label>
<div class="row" style="margin-top:10px"><button class="s nf" onclick="upd()" data-t="updall"></button></div>
<div class="mu" style="margin-top:6px" data-t="updnote"></div></div>
</div>

<details id="dt" class="card"><summary data-t="details"></summary><div id="cur2" class="mu"></div><pre id="log"></pre><div id="alts"></div><div id="fails"></div></details>
<footer>Media Downloader · by <a href="https://github.com/Bibinho1999" target="_blank" rel="noopener">Bibinho1999</a></footer>
</div>

<div id="bar"><div class="in"><div class="st"><b id="stline"></b><progress id="bar2" max="100" value="0"></progress><div id="cur"></div></div>
<button id="go" class="big" onclick="go()"></button><button id="stopb" class="s" onclick="api('stop',{})" data-t="stop"></button><button class="s" onclick="api('open',{what:'dl'})" data-t="openfolder"></button></div></div>

<script>
const T='__TOK__',$=i=>document.getElementById(i);
const D={"pt": {"lang": "Idioma", "quit": "Sair", "quit_q": "Encerrar o programa?", "sub": "Baixe músicas e vídeos de mais de mil sites, só colando o link.", "t_links": "Baixar", "t_pick": "Playlist", "t_cfg": "Configurações", "s1_links": "Cole o link", "s1_pick": "Carregue a playlist", "s2": "Escolha o que você quer", "urlsph": "Cole aqui um ou mais links (um por linha). Pode ser vídeo, música ou playlist, de qualquer site.", "chk": "Verificar link", "ka": "Música (só áudio)", "kv": "Vídeo", "afmt": "Formato da música", "f_mp3": "MP3 (funciona em tudo)", "f_m4a": "M4A (boa qualidade)", "f_flac": "FLAC (sem perdas)", "f_wav": "WAV (sem compressão)", "aq": "Qualidade do áudio", "q_best": "Melhor", "q_high": "Alta (320 kbps)", "q_mid": "Média (192 kbps)", "q_low": "Menor arquivo (128 kbps)", "vq": "Qualidade do vídeo", "vcont": "Formato do vídeo", "mp4o": "MP4 (funciona em tudo)", "mkvo": "MKV (original, sem converter)", "qnote": "Dica: muitos sites oferecem áudio de cerca de 128–160 kbps, então qualidades maiores podem não melhorar o som.", "more": "Mais opções (pastas, numeração, intervalo...)", "plm": "Onde guardar playlists e canais", "plm1": "Numa pasta com o nome da playlist (retoma se já existir)", "plm2": "Numa pasta nova a cada vez (nome + data e hora)", "plm3": "Sem pasta (tudo solto)", "num": "Numerar os arquivos pela ordem da playlist", "batch": "Ao colar vários links, guardar tudo numa pasta \"Lote data-hora\"", "split": "Separar em subpastas Músicas e Vídeos", "from": "Começar no item", "to": "Parar no item", "all": "todos", "nopl": "Baixar só o vídeo do link (ignorar a playlist)", "plph": "Link da playlist, álbum ou canal", "plload": "Carregar lista", "stop": "Parar", "plhint": "Cole o link e clique em Carregar lista. Depois marque as faixas e escolha áudio ou vídeo.", "selall": "Marcar todos", "selnone": "Desmarcar", "selinv": "Inverter", "filt": "Filtrar por título ou canal", "as": "Baixar como:", "pm_a": "Tudo em áudio", "pm_v": "Tudo em vídeo", "pm_m": "Misturado (escolho em cada faixa)", "th_title": "Título", "th_ch": "Canal", "th_dur": "Duração", "th_type": "Tipo", "h_look": "Aparência", "theme": "Tema", "th_auto": "Automático (segue o Windows)", "th_light": "Claro", "th_dark": "Escuro", "th_neon": "Neon", "fsize": "Tamanho do texto", "fs_s": "Pequeno", "fs_m": "Normal", "fs_l": "Grande", "fs_xl": "Muito grande", "dens": "Espaçamento", "d_comfy": "Confortável", "d_compact": "Compacto", "corner": "Cantos", "c_round": "Arredondados", "c_square": "Retos", "accent": "Cor de destaque", "reset_look": "Restaurar aparência", "h_where": "Arquivos e abertura", "dldir": "Pasta de downloads (vazio = a pasta Downloads ao lado do programa)", "openm": "Como abrir o programa (vale na próxima vez que abrir)", "openm_a": "Janela própria (WebView2 embutido no .exe; sem ele, Edge/Chrome em modo aplicativo)", "openm_b": "Aba do navegador padrão", "shortc": "Criar atalhos (Área de Trabalho e Menu Iniciar)", "openbin": "Abrir pasta do programa", "h_behav": "Comportamento", "meta": "Colocar capa e informações (artista, título) no arquivo", "safe": "Modo cuidadoso: faz pausas entre os downloads para evitar bloqueio", "alt": "Se um vídeo estiver bloqueado ou removido, procurar uma versão alternativa", "addid": "Colocar o ID do vídeo no nome do arquivo", "reset": "Começar do zero (ignorar o histórico do que já foi baixado)", "selfupd": "Verificar e baixar atualizações do próprio programa ao abrir (vale na próxima abertura)", "h_acc": "Contas e cookies (só se precisar)", "accnote": "Serve para vídeos privados, com restrição de idade ou quando um site pede login. O programa usa o login do seu navegador, tentando um por vez nesta ordem.", "nock": "Tentar sem cookies primeiro", "wait": "Se todos falharem, esperar quantos minutos antes de tentar de novo? (0 = parar)", "cknote": "Se existir um cookies.txt ao lado do programa, ele é usado primeiro. Navegadores baseados em Chrome podem exigir que estejam fechados; o Firefox é o mais estável.", "h_upd": "Atualizações", "chan": "Canal de atualização do yt-dlp", "chan_s": "Estável", "chan_n": "Nightly (recebe correções mais rápido)", "updall": "Atualizar tudo agora", "updnote": "O yt-dlp, o ffmpeg e o deno são comparados com a versão mais recente toda vez que o programa abre (e a cada 6 horas se ficar aberto) e atualizados sozinhos quando há novidade. Se um download falhar por extrator desatualizado, o yt-dlp é atualizado e o link é tentado de novo automaticamente. O botão abaixo força a verificação agora.", "details": "Ver detalhes do andamento", "openfolder": "Abrir pasta", "go": "Baixar", "go_pick": "Baixar selecionados", "idle": "Pronto para baixar", "a_pick": "Carregue uma playlist e marque pelo menos uma faixa.", "a_links": "Cole ao menos um link.", "ck_ing": "Verificando...", "ck_err": "Não consegui ler o link: ", "ck_cnt": " item(ns)", "ck_slow": "Demorou demais.", "pl_need": "Cole o link da playlist.", "pl_load": "Carregando a lista...", "pl_fail": "Não consegui carregar: ", "pl_loading": "Carregando... ", "pl_tracks": " faixa(s) · ", "pl_marked": " marcada(s) (", "pl_audio": " áudio, ", "pl_video": " vídeo)", "unavail": "indisponível", "opt_a": "Áudio", "opt_v": "Vídeo", "closed": "Programa encerrado.", "cookies": "cookies: ", "item": "item ", "nocookie": "sem cookies", "ok": "ok", "miss": "falta", "fails": "Não foi possível baixar:\n", "alts": "Versões alternativas baixadas:\n", "noff": "Atenção: o ffmpeg não está instalado (o download falhou). A conversão para MP3/MP4 pode falhar. Vá em Configurações > Atualizar tudo agora para tentar de novo."}, "en": {"lang": "Language", "quit": "Quit", "quit_q": "Quit the program?", "sub": "Download music and videos from over a thousand sites, just by pasting the link.", "t_links": "Download", "t_pick": "Playlist", "t_cfg": "Settings", "s1_links": "Paste the link", "s1_pick": "Load the playlist", "s2": "Choose what you want", "urlsph": "Paste one or more links here (one per line). Video, song or playlist, from any site.", "chk": "Check link", "ka": "Music (audio only)", "kv": "Video", "afmt": "Music format", "f_mp3": "MP3 (works everywhere)", "f_m4a": "M4A (good quality)", "f_flac": "FLAC (lossless)", "f_wav": "WAV (uncompressed)", "aq": "Audio quality", "q_best": "Best", "q_high": "High (320 kbps)", "q_mid": "Medium (192 kbps)", "q_low": "Smallest file (128 kbps)", "vq": "Video quality", "vcont": "Video format", "mp4o": "MP4 (works everywhere)", "mkvo": "MKV (original, no conversion)", "qnote": "Tip: many sites offer audio of around 128–160 kbps, so higher qualities may not improve the sound.", "more": "More options (folders, numbering, range...)", "plm": "Where to keep playlists and channels", "plm1": "In a folder named after the playlist (resumes if it exists)", "plm2": "In a new folder every time (name + date and time)", "plm3": "No folder (everything loose)", "num": "Number the files in playlist order", "batch": "When pasting several links, keep everything in a \"Batch date-time\" folder", "split": "Split into Music and Videos subfolders", "from": "Start at item", "to": "Stop at item", "all": "all", "nopl": "Download only the video in the link (ignore the playlist)", "plph": "Playlist, album or channel link", "plload": "Load list", "stop": "Stop", "plhint": "Paste the link and click Load list. Then tick the tracks and choose audio or video.", "selall": "Select all", "selnone": "Select none", "selinv": "Invert", "filt": "Filter by title or channel", "as": "Download as:", "pm_a": "All as audio", "pm_v": "All as video", "pm_m": "Mixed (I choose per track)", "th_title": "Title", "th_ch": "Channel", "th_dur": "Length", "th_type": "Type", "h_look": "Appearance", "theme": "Theme", "th_auto": "Automatic (follows Windows)", "th_light": "Light", "th_dark": "Dark", "th_neon": "Neon", "fsize": "Text size", "fs_s": "Small", "fs_m": "Normal", "fs_l": "Large", "fs_xl": "Extra large", "dens": "Spacing", "d_comfy": "Comfortable", "d_compact": "Compact", "corner": "Corners", "c_round": "Rounded", "c_square": "Square", "accent": "Accent color", "reset_look": "Reset appearance", "h_where": "Files and opening", "dldir": "Downloads folder (empty = the Downloads folder next to the program)", "openm": "How to open the program (applies the next time it opens)", "openm_a": "Own window (WebView2 built into the .exe; without it, Edge/Chrome in app mode)", "openm_b": "Default browser tab", "shortc": "Create shortcuts (Desktop and Start Menu)", "openbin": "Open program folder", "h_behav": "Behavior", "meta": "Put cover art and info (artist, title) in the file", "safe": "Careful mode: pauses between downloads to avoid being blocked", "alt": "If a video is blocked or removed, look for an alternative version", "addid": "Put the video ID in the file name", "reset": "Start over (ignore the history of what was already downloaded)", "selfupd": "Check for and download updates of the program itself when it opens (applies on next opening)", "h_acc": "Accounts and cookies (only if needed)", "accnote": "For private or age-restricted videos, or when a site asks you to sign in. The program borrows the login from your browser, trying one at a time in this order.", "nock": "Try without cookies first", "wait": "If all fail, how many minutes to wait before trying again? (0 = stop)", "cknote": "If a cookies.txt sits next to the program, it is used first. Chrome-based browsers may need to be closed; Firefox is the most stable.", "h_upd": "Updates", "chan": "yt-dlp update channel", "chan_s": "Stable", "chan_n": "Nightly (gets fixes sooner)", "updall": "Update everything now", "updnote": "yt-dlp, ffmpeg and deno are compared with the latest version every time the program opens (and every 6 hours while it stays open) and updated by themselves when there is a newer one. If a download fails because of an outdated extractor, yt-dlp is updated and the link is retried automatically. The button below forces a check now.", "details": "Show progress details", "openfolder": "Open folder", "go": "Download", "go_pick": "Download selected", "idle": "Ready to download", "a_pick": "Load a playlist and tick at least one track.", "a_links": "Paste at least one link.", "ck_ing": "Checking...", "ck_err": "Could not read the link: ", "ck_cnt": " item(s)", "ck_slow": "Took too long.", "pl_need": "Paste the playlist link.", "pl_load": "Loading the list...", "pl_fail": "Could not load: ", "pl_loading": "Loading... ", "pl_tracks": " track(s) · ", "pl_marked": " selected (", "pl_audio": " audio, ", "pl_video": " video)", "unavail": "unavailable", "opt_a": "Audio", "opt_v": "Video", "closed": "Program closed.", "cookies": "cookies: ", "item": "item ", "nocookie": "no cookies", "ok": "ok", "miss": "missing", "fails": "Could not download:\n", "alts": "Alternative versions downloaded:\n", "noff": "Warning: ffmpeg is not installed (the download failed). Converting to MP3/MP4 may fail. Go to Settings > Update everything now to try again."}};
const LOGO='data:image/png;base64,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';$('logo').src=LOGO;$('fav').href=LOGO;
let LANG='en';
const t=k=>(D[LANG]&&D[LANG][k])||D.en[k]||k;
const api=(p,b)=>fetch('/api/'+p+(p.indexOf('?')<0?'?':'&')+'t='+T,b?{method:'POST',body:JSON.stringify(b)}:{}).then(r=>r.json());
const esc=s=>String(s==null?'':s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
let cur='links',P={items:[],from:0,busy:false,title:'',url:''},ready=false,running=false,lastStatus=null;
const IDS=['selfUpd','lang','openMode','theme','accent','fsize','density','corner','afmt','aq','vq','vcont','plmode','num','batch','splitType','st','en','noPl','nock','wait','meta','safe','reset','alt','addId','dlDir','chan'];
const FS={s:14,m:16,l:18,xl:20};
function applyLook(){const h=document.documentElement,th=$('theme').value;
if(th==='auto')h.removeAttribute('data-theme');else h.setAttribute('data-theme',th);
h.style.fontSize=(FS[$('fsize').value]||16)+'px';
if($('density').value==='compact')h.setAttribute('data-dens','compact');else h.removeAttribute('data-dens');
if($('corner').value==='square')h.setAttribute('data-corner','square');else h.removeAttribute('data-corner');
const c=$('accent').value||'#0e7490';h.style.setProperty('--ac',c);
const n=parseInt(c.slice(1),16),r=n>>16,g=(n>>8)&255,b=n&255,L=(0.299*r+0.587*g+0.114*b);h.style.setProperty('--acfg',L>150?'#111':'#fff');
document.querySelectorAll('#sw button[data-c]').forEach(x=>{x.style.background=x.dataset.c;x.classList.toggle('on',x.dataset.c.toLowerCase()===c.toLowerCase())})}
function resetLook(){$('theme').value='auto';$('fsize').value='m';$('density').value='comfy';$('corner').value='round';$('accent').value='#0e7490';applyLook();save()}
document.querySelectorAll('#sw button[data-c]').forEach(x=>x.addEventListener('click',()=>{$('accent').value=x.dataset.c;applyLook();save()}));
function radio(n){const e=document.querySelector('input[name='+n+']:checked');return e?e.value:''}
function setRadio(n,v){document.querySelectorAll('input[name='+n+']').forEach(e=>e.checked=e.value===v)}
function updFmt(){const L=cur==='links',k=radio('kind'),pm=radio('pm');
const a=L?k==='a':pm!=='v',v=L?k==='v':pm!=='a';
$('gA').classList.toggle('hide',!a);$('gV').classList.toggle('hide',!v);
$('kindbox').classList.toggle('hide',!L);$('rowRange').classList.toggle('hide',!L);$('rowNoPl').classList.toggle('hide',!L);
$('rowSplit').classList.toggle('hide',L);$('rowBatch').classList.toggle('hide',!L)}
function applyLang(){document.documentElement.lang=LANG;
document.querySelectorAll('[data-t]').forEach(e=>e.textContent=t(e.dataset.t));
document.querySelectorAll('[data-ph]').forEach(e=>e.placeholder=t(e.dataset.ph));
$('go').textContent=cur==='pick'?t('go_pick'):t('go');
if(P.items.length){render()}else if(!P.busy){$('plinfo').textContent=t('plhint')}
if(lastStatus)showStatus(lastStatus)}
function tab(k){cur=k;for(const x of['links','pick','cfg']){$('p_'+x).classList.toggle('on',x===k);$('t_'+x).classList.toggle('on',x===k)}
$('s2').classList.toggle('hide',k==='cfg');$('go').textContent=k==='pick'?t('go_pick'):t('go');updFmt()}
function common(){const o={};for(const i of IDS){const e=$(i);o[i]=e.type==='checkbox'?e.checked:e.value}
o.browsers=[...document.querySelectorAll('.br:checked')].map(e=>e.value);o.kind=radio('kind');o.pm=radio('pm');o.plurl=$('plurl').value;return o}
let sv=null;function save(){clearTimeout(sv);sv=setTimeout(()=>api('settings',common()),400)}
async function load(){try{const s=await api('settings');for(const i of IDS){if(!(i in s))continue;const e=$(i);if(e.type==='checkbox')e.checked=!!s[i];else e.value=s[i]}
if(s.browsers)document.querySelectorAll('.br').forEach(e=>e.checked=s.browsers.indexOf(e.value)>=0);if(s.kind)setRadio('kind',s.kind);if(s.pm)setRadio('pm',s.pm);if(s.plurl)$('plurl').value=s.plurl}catch(e){}
LANG=$('lang').value||'en';if(!D[LANG])LANG='en';$('lang').value=LANG;applyLook();applyLang();updFmt();
document.querySelectorAll('input,select').forEach(e=>{e.addEventListener('change',save);if(e.type==='color')e.addEventListener('input',()=>{applyLook();save()})});
['theme','fsize','density','corner'].forEach(i=>$(i).addEventListener('change',applyLook));
$('lang').addEventListener('change',()=>{LANG=$('lang').value;applyLang();save()});
document.querySelectorAll('input[name=kind]').forEach(e=>e.addEventListener('change',updFmt))}
function opts(){const o=common();o.urls=$('urls').value.split('\n').map(s=>s.trim()).filter(s=>s&&s[0]!=='#');return o}
async function go(){if(running)return;let o;
if(cur==='pick'){const sel=P.items.filter(x=>x.checked&&!x.unavail);if(!sel.length)return alert(t('a_pick'));
o=common();o.mode='pick';o.plUrl=P.url||$('plurl').value;o.plTitle=P.title;o.maxIdx=Math.max.apply(null,P.items.map(x=>x.idx||0).concat([P.items.length]));
o.items=sel.map(x=>({idx:x.idx,title:x.title,url:x.url,type:x.type}))}
else{o=opts();o.mode='links';if(!o.urls.length){$('urls').focus();return alert(t('a_links'))}}
const r=await api('start',o);if(r.error)alert(r.error)}
async function chk(){const u=opts().urls[0];if(!u)return;$('ck').textContent=t('ck_ing');await api('info',{url:u});
for(let i=0;i<90;i++){await new Promise(r=>setTimeout(r,700));const r=await api('infostate');if(!r.busy){$('ck').textContent=r.error?(t('ck_err')+r.error):(r.title+' · '+r.count+t('ck_cnt')+(r.ex?' · '+r.ex:''));return}}$('ck').textContent=t('ck_slow')}
async function upd(){const r=await api('update',{});if(r.error)alert(r.error)}
async function shortcuts(){const r=await api('shortcut',{});alert(r.msg||r.error||'ok')}
/* ---- playlist tab ---- */
async function plLoad(){const u=$('plurl').value.trim();if(!u)return alert(t('pl_need'));P={items:[],from:0,busy:true,title:'',url:u};render();$('plinfo').textContent=t('pl_load');await api('pl/load',{url:u,browsers:common().browsers,nock:$('nock').checked});plPoll()}
async function plPoll(){try{const r=await api('pl?from='+P.from);const pm=radio('pm');
for(const it of r.items){it.checked=!it.unavail;it.type=pm==='v'?'v':'a';P.items.push(it)}P.from=r.total;P.title=r.title||P.title;P.busy=r.busy;P.err=r.err;render()
if(r.busy)setTimeout(plPoll,700);else if(!P.items.length&&r.err)$('plinfo').textContent=t('pl_fail')+r.err}catch(e){}}
function vis(){const q=$('plfilter').value.trim().toLowerCase();return P.items.map((x,i)=>[x,i]).filter(p=>!q||(p[0].title+' '+p[0].uploader).toLowerCase().indexOf(q)>=0)}
function render(){const v=vis();$('tb').innerHTML=v.map(p=>{const x=p[0],i=p[1];return`<tr class="${x.unavail?'na':''}"><td><input type="checkbox" data-i="${i}" ${x.checked?'checked':''} ${x.unavail?'disabled':''}></td><td class="num">${esc(x.idx)}</td><td>${esc(x.title)}</td><td>${esc(x.uploader)}</td><td>${esc(x.dur)}</td><td>${x.unavail?t('unavail'):`<select data-t2="${i}"><option value="a" ${x.type==='a'?'selected':''}>${t('opt_a')}</option><option value="v" ${x.type==='v'?'selected':''}>${t('opt_v')}</option></select>`}</td></tr>`}).join('');sum()}
function sum(){const s=P.items.filter(x=>x.checked&&!x.unavail),a=s.filter(x=>x.type==='a').length;
if(P.items.length)$('plinfo').textContent=(P.busy?t('pl_loading'):'')+(P.title?'“'+P.title+'” · ':'')+P.items.length+t('pl_tracks')+s.length+t('pl_marked')+a+t('pl_audio')+(s.length-a)+t('pl_video')}
function mark(m){for(const p of vis()){const x=p[0];if(x.unavail)continue;x.checked=m===2?!x.checked:!!m}render()}
$('tb').addEventListener('change',e=>{const g=e.target;if(g.dataset.i!==undefined){P.items[+g.dataset.i].checked=g.checked;sum()}
else if(g.dataset.t2!==undefined){P.items[+g.dataset.t2].type=g.value;setRadio('pm','m');updFmt();save();sum()}});
document.querySelectorAll('input[name=pm]').forEach(e=>e.addEventListener('change',()=>{const m=radio('pm');if(m!=='m'){P.items.forEach(x=>x.type=m);render()}updFmt()}));
/* ---- status ---- */
function showStatus(s){$('bar2').value=s.pct;
const nb=s.prep||s.note||((s.ver&&s.ver.ytdlp&&!s.ver.ffmpeg)?t('noff'):'');$('banner').style.display=nb?'block':'none';$('banner').textContent=nb;
$('ver').textContent=s.ver&&s.ver.ytdlp?('· yt-dlp '+s.ver.ytdlp+' · ffmpeg '+(s.ver.ffmpeg?String(s.ver.ffmpeg).slice(0,14):t('miss'))+' · deno '+(s.ver.deno?s.ver.deno:t('miss'))):'';
const idle=(s.status==='Idle'||s.status==='Parado');
let line=idle?t('idle'):s.status;
if(s.running&&s.total>0)line+=' · '+(s.done+1>s.total?s.total:s.done+1)+'/'+s.total;
if(s.running&&s.item)line+=' ('+t('item')+s.item+')';
if(s.running&&s.speed)line+=' · '+s.speed+(s.eta?' · ETA '+s.eta:'');
if(s.running&&s.browser&&s.browser!==t('nocookie')&&s.browser!=='sem cookies'&&s.browser!=='no cookies')line+=' · '+t('cookies')+s.browser;
$('stline').textContent=line;$('cur').textContent=s.cur||'';$('cur2').textContent=s.cur||'';
$('log').textContent=s.log.join('\n');if($('dt').open)$('log').scrollTop=1e9;
$('fails').textContent=s.fails.length?t('fails')+s.fails.join('\n'):'';$('alts').textContent=s.alts.length?t('alts')+s.alts.join('\n'):'';
if(s.fails.length||s.alts.length)$('dt').open=true;
$('go').disabled=s.running||!s.ready;$('stopb').disabled=!s.running}
async function poll(){try{const s=await api('status');running=s.running;ready=s.ready;lastStatus=s;showStatus(s)}catch(e){$('stline').textContent=t('closed')}}
$('tb').addEventListener('change',()=>{});
load();setInterval(poll,1000);poll();

(function(){ if(window.chrome&&window.chrome.webview) return; var tm; function sv(){ clearTimeout(tm); tm=setTimeout(function(){ try{ api('winsize',{x:window.screenX,y:window.screenY,w:window.outerWidth,h:window.outerHeight}) }catch(e){} },700) } window.addEventListener('resize',sv); })();
</script></body></html>
'@
function Bg($sb,$a){ $rsp=[runspacefactory]::CreateRunspace(); $rsp.Open(); $p=[powershell]::Create(); $p.Runspace=$rsp
 [void]$p.AddScript($sb.ToString()); foreach($x in $a){ [void]$p.AddArgument($x) }; [void]$p.BeginInvoke() }
function ReadSettings{ if(Test-Path $settingsFile){ try{ return (Get-Content $settingsFile -Raw -Encoding UTF8|ConvertFrom-Json) }catch{} }; return $null }
function GetDl{ $s=ReadSettings; $d=$null; if($s -and $s.dlDir){ $d="$($s.dlDir)".Trim() }
 if(-not $d){ $d=[IO.Path]::Combine($dir,'Downloads') }
 try{ New-Item -ItemType Directory -Force $d | Out-Null }catch{ $d=[IO.Path]::Combine($dir,'Downloads'); New-Item -ItemType Directory -Force $d | Out-Null }
 return $d }
$wvScript=@'
param($Url,$Bin)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$pt=$false; try{ $pt=((Get-Content (Join-Path $Bin 'settings.json') -Raw) -replace '\s','') -match '"lang":"pt"' }catch{}
function T($p,$e){ if($pt){ $p }else{ $e } }
$winf=Join-Path $Bin 'win.txt'
function GetWin{ try{ $a=(Get-Content $winf -Raw).Trim().Split(','); if($a.Count -ge 4){ $r=@{x=[int]$a[0];y=[int]$a[1];w=[int]$a[2];h=[int]$a[3];m=($a.Count -ge 5 -and $a[4] -eq '1')}; if($r.w -ge 600 -and $r.h -ge 500){ return $r } } }catch{}; return $null }
function Fallback{
 $w=GetWin; $ar=@("--app=$Url",'--no-first-run',"--user-data-dir=`"$(Join-Path $Bin 'appwin')`"")
 if($w){ $ar+="--window-size=$($w.w),$($w.h)"; $ar+="--window-position=$($w.x),$($w.y)" }else{ $ar+='--window-size=1040,940' }
 foreach($rel in 'Microsoft\Edge\Application\msedge.exe','Google\Chrome\Application\chrome.exe'){ foreach($root in $env:ProgramFiles,${env:ProgramFiles(x86)},$env:LocalAppData){ if($root){ $c=Join-Path $root $rel; if(Test-Path $c){ Start-Process $c -ArgumentList $ar; return } } } }
 Start-Process $Url }
function RtOk{ foreach($k in 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}','HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}','HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'){ try{ $v=(Get-ItemProperty $k -ea Stop).pv; if($v -and $v -ne '0.0.0.0'){ return $true } }catch{} }; return $false }
try{
 $d=Join-Path $Bin 'wv2'; $core=Join-Path $d 'Microsoft.Web.WebView2.Core.dll'; $wf=Join-Path $d 'Microsoft.Web.WebView2.WinForms.dll'
 for($i=0;$i -lt 240 -and -not ((Test-Path $core) -and (Test-Path $wf)) -and -not (Test-Path (Join-Path $d 'fail.txt'));$i++){ Start-Sleep -Milliseconds 250 }
 if(-not ((Test-Path $core) -and (Test-Path $wf))){ Fallback; return }
 if(-not (RtOk)){
  $dec=Join-Path $d 'declined.txt'
  if((Test-Path $dec) -and ((Get-Date)-(Get-Item $dec).LastWriteTime).TotalDays -lt 30){ Fallback; return }
  $r=[Windows.Forms.MessageBox]::Show((T "Para abrir o Media Downloader em uma janela propria e preciso o Microsoft Edge WebView2 Runtime (gratuito, da Microsoft).`n`nInstalar a ultima versao agora?" "To open Media Downloader in its own window it needs the Microsoft Edge WebView2 Runtime (free, from Microsoft).`n`nInstall the latest version now?"),'Media Downloader','YesNo','Question')
  if($r -ne 'Yes'){ Set-Content $dec (Get-Date -Format s); Fallback; return }
  $tmp=Join-Path ([IO.Path]::GetTempPath()) 'MicrosoftEdgeWebview2Setup.exe'
  try{ [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12 }catch{}
  try{ (New-Object Net.WebClient).DownloadFile('https://go.microsoft.com/fwlink/p/?LinkId=2124703',$tmp); Start-Process $tmp -ArgumentList '/silent','/install' -Wait }catch{}
  if(-not (RtOk)){ [void][Windows.Forms.MessageBox]::Show((T 'Nao consegui instalar o WebView2. Vou abrir no Edge/Chrome.' 'Could not install WebView2. Opening in Edge/Chrome instead.'),'Media Downloader'); Fallback; return }
 }
 Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class Nat{ [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] public static extern bool SetDllDirectory(string p); }'
 $arch=$(if([Environment]::Is64BitProcess){ 'x64' }else{ 'x86' })
 [void][Nat]::SetDllDirectory((Join-Path $d $arch))
 [void][Reflection.Assembly]::LoadFrom($core); $asm=[Reflection.Assembly]::LoadFrom($wf)
 $tWv=$asm.GetType('Microsoft.Web.WebView2.WinForms.WebView2',$true); $tCp=$asm.GetType('Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties',$true)
 $cp=[Activator]::CreateInstance($tCp); $tCp.GetProperty('UserDataFolder').SetValue($cp,(Join-Path $Bin 'wv2data'),$null)
 $wv=[Activator]::CreateInstance($tWv); $tWv.GetProperty('CreationProperties').SetValue($wv,$cp,$null); $wv.Dock='Fill'
 $f=New-Object Windows.Forms.Form; $f.Text='Media Downloader'
 try{ $f.Icon=[Drawing.Icon]::ExtractAssociatedIcon((Join-Path $Bin 'app.ico')) }catch{}
 $w=GetWin; $f.StartPosition='CenterScreen'; $f.Width=1080; $f.Height=980
 if($w){ $vis=$false; foreach($sc in [Windows.Forms.Screen]::AllScreens){ if($sc.WorkingArea.IntersectsWith((New-Object Drawing.Rectangle $w.x,$w.y,$w.w,$w.h))){ $vis=$true } }
  if($vis){ $f.StartPosition='Manual'; $f.Left=$w.x; $f.Top=$w.y; $f.Width=$w.w; $f.Height=$w.h; if($w.m){ $f.WindowState='Maximized' } } }
 $f.Controls.Add($wv)
 $save={ try{ $b=$(if($f.WindowState -eq 'Normal'){ $f.Bounds }else{ $f.RestoreBounds }); $m=$(if($f.WindowState -eq 'Maximized'){ 1 }else{ 0 }); Set-Content $winf "$($b.X),$($b.Y),$($b.Width),$($b.Height),$m" }catch{} }
 $f.add_FormClosing($save); $f.add_ResizeEnd($save)
 $tWv.GetProperty('Source').SetValue($wv,[Uri]$Url,$null)
 $script:ticks=0; $tm=New-Object Windows.Forms.Timer; $tm.Interval=1000
 $tm.add_Tick({ $script:ticks++; $c=$null; try{ $c=$tWv.GetProperty('CoreWebView2').GetValue($wv,$null) }catch{}
  if($c){ $tm.Stop() } elseif($script:ticks -ge 30){ $tm.Stop(); Fallback; $f.Close() } })
 $tm.Start()
 [Windows.Forms.Application]::Run($f)
}catch{ try{ Add-Content (Join-Path $Bin 'app.log') ("wvwin: "+$_.Exception.Message) }catch{}; Fallback }
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
# ------------------------------------------------------------------ inicio
Write-Host "== Media Downloader $APPVER - by Bibinho1999 =="
$S.chan=$(if($(ReadSettings).chan){ "$((ReadSettings).chan)" }else{ 'stable' })
$S.lang=$(if($(ReadSettings).lang -eq 'pt'){ 'pt' }else{ 'en' })
$S.selfUpd=-not ($(ReadSettings).selfUpd -eq $false)
$S.icoB64=$icoB64.Trim()
if($self -and $self -match '\.(bat|ps1|cmd)$' -and (Test-Path $self) -and -not $env:YTDL_EXE){
 $raw=[IO.File]::ReadAllText($self,[Text.Encoding]::UTF8); $ix=$raw.LastIndexOf('###'+'PS###')
 $S.payload=$(if($ix -ge 0){ $raw.Substring($ix+8) }else{ $raw }) }
Bg $prepSb @($S,$lib,$false)
if(($WIN -and -not $TEST) -or $env:YTDL_WV2TEST){ Bg $wv2Sb @($S,$lib) }
if(-not $TEST){ Bg $schedSb @($S,$lib,$prepSb.ToString()) }
$lst=$null; $port=8765
while($port -lt 8790){ $l=New-Object Net.HttpListener; $l.Prefixes.Add("http://127.0.0.1:$port/"); try{ $l.Start(); $lst=$l; break }catch{ $port++ } }
if(-not $lst){ Write-Host 'ERROR: no free port (8765-8789) / nenhuma porta livre.'; return }
[IO.File]::WriteAllText([IO.Path]::Combine($bin,'port.txt'),"$port")
Write-Host "Ready! Opening http://127.0.0.1:$port/"
if($S.payload -and -not $TEST -and $WIN){ Bg $exeSb @($S,$lib,$cs,$csBasic); Write-Host '(building/updating Media-Downloader.exe in the background)' }
if(-not $env:YTDL_EXE -and (-not $TEST -or $env:YTDL_BROWSER)){ Open-Ui $port }

$flagSc=[IO.Path]::Combine($bin,'shortcuts.done')
if($WIN -and -not $TEST -and -not(Test-Path $flagSc)){ try{ [void](Make-Shortcuts $false); Set-Content $flagSc (Get-Date -Format s); Write-Host 'Shortcuts created on the Desktop and Start Menu.' }catch{} }
$first=$true
while($lst.IsListening){
 $ctx=$lst.GetContext(); $rq=$ctx.Request; $rs=$ctx.Response
 try{
  $path=$rq.Url.AbsolutePath; $body=''
  if($rq.HasEntityBody){ $body=(New-Object IO.StreamReader($rq.InputStream,[Text.Encoding]::UTF8)).ReadToEnd() }
  $out='{}'; $ct='application/json; charset=utf-8'
  $hostOk=("$($rq.Headers['Host'])" -match '^(127\.0\.0\.1|localhost)(:\d+)?$')
  if(-not $hostOk){ $rs.StatusCode=403; $out='' }
  elseif($path -eq '/'){ $out=$html.Replace('__TOK__',$tok); $ct='text/html; charset=utf-8' }
  elseif($rq.QueryString['t'] -ne $tok){ $rs.StatusCode=403 }
  else{
   switch($path){
    '/api/status'{ $out=@{running=$S.running;ready=$S.ready;prep=$S.prep;note=$S.note;ver=$S.ver;status=$S.status;pct=$S.pct;speed=$S.speed;eta=$S.eta;item=$S.item;cur=$S.cur;browser=$S.browser;done=$S.done;total=$S.total;
       log=@($S.log.ToArray()|Select-Object -Last 90);fails=@($S.fails.ToArray());alts=@($S.alts.ToArray())}|ConvertTo-Json -Depth 4 -Compress }
    '/api/settings'{ if($rq.HttpMethod -eq 'POST'){ try{ $null=$body|ConvertFrom-Json; [IO.File]::WriteAllText($settingsFile,$body,(New-Object Text.UTF8Encoding $false)); $sj=$body|ConvertFrom-Json; if($sj.chan){ $S.chan="$($sj.chan)" }; $S.lang=$(if($sj.lang -eq 'pt'){ 'pt' }else{ 'en' }); if($sj.PSObject.Properties['selfUpd']){ $S.selfUpd=[bool]$sj.selfUpd } }catch{} }
       else{ if(Test-Path $settingsFile){ $out=[IO.File]::ReadAllText($settingsFile,[Text.Encoding]::UTF8) } } }
    '/api/start'{
     if($S.running){ $out=@{error=(Tr 'Ja existe um download em andamento.' 'A download is already running.')}|ConvertTo-Json -Compress }
     elseif(-not $S.ready){ $out=@{error=(Tr 'Ainda preparando o yt-dlp/ffmpeg. Aguarde alguns instantes.' 'Still preparing yt-dlp/ffmpeg. Please wait a moment.')}|ConvertTo-Json -Compress }
     else{ $o=$body|ConvertFrom-Json; $S.running=$true; $S.status=(Tr 'Iniciando' 'Starting'); Bg $worker @($S,$lib,$o,(GetDl),$arc); $out='{"ok":true}' } }
    '/api/stop'{ $S.stop=$true; $PL.stop=$true; KillTree $S.pid; KillTree $S.lpid }
    '/api/open'{ $w=($body|ConvertFrom-Json).what; if($w -eq 'bin'){ Open-Folder $bin }else{ Open-Folder (GetDl) } }
    '/api/info'{ $u=($body|ConvertFrom-Json).url; if(-not $S.info.busy){ $S.info=@{busy=$true}; Bg $infoSb @($S,$lib,$u,@(),$dir) } }
    '/api/infostate'{ $out=$S.info|ConvertTo-Json -Compress }
    '/api/pl/load'{ $b=$body|ConvertFrom-Json; if(-not $PL.busy){ $PL.busy=$true; Bg $plSb @($S,$PL,$lib,$b.url,@($b.browsers),[bool]$b.nock,$dir) } }
    '/api/pl'{ $f=0; [void][int]::TryParse($rq.QueryString['from'],[ref]$f); $all=@($PL.items.ToArray()); $sl=@(); if($f -lt $all.Count){ $sl=@($all[$f..($all.Count-1)]) }
       $out=@{items=$sl;total=$all.Count;title="$($PL.title)";busy=[bool]$PL.busy;err="$($PL.err)"}|ConvertTo-Json -Depth 4 -Compress }
    '/api/pl/stop'{ $PL.stop=$true; KillTree $S.lpid }
    '/api/update'{ if($S.running){ $out=@{error=(Tr 'Espere o download terminar para atualizar.' 'Wait for the download to finish before updating.')}|ConvertTo-Json -Compress }else{ Bg $prepSb @($S,$lib,$true) } }
    '/api/winsize'{ try{ $o=$body|ConvertFrom-Json; if($o.w -ge 600 -and $o.h -ge 500){ Set-Content ([IO.Path]::Combine($bin,'win.txt')) "$([int]$o.x),$([int]$o.y),$([int]$o.w),$([int]$o.h),0" } }catch{} }
    '/api/shortcut'{ $out=@{msg=(Make-Shortcuts $false)}|ConvertTo-Json -Compress }
    '/api/quit'{ $S.stop=$true; $PL.stop=$true; KillTree $S.pid; KillTree $S.lpid; KillTree $S.ipid; $lst.Stop() }
   }
  }
  if($lst.IsListening -and $out){ $b=[Text.Encoding]::UTF8.GetBytes($out); $rs.ContentType=$ct; $rs.OutputStream.Write($b,0,$b.Length) }
 }catch{ try{ $rs.StatusCode=500 }catch{} }
 finally{ try{ $rs.Close() }catch{} }
}
try{ Remove-Item ([IO.Path]::Combine($bin,'port.txt')) -ea 0 }catch{}
