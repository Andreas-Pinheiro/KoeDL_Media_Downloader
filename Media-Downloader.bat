@echo off
rem Media Downloader - by Andreas-Pinheiro - github.com/Andreas-Pinheiro/Media-Downloader
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
  $u=$(if($env:YTDL_UPDURL){ $env:YTDL_UPDURL }else{ 'https://raw.githubusercontent.com/Andreas-Pinheiro/Media-Downloader/main/Media-Downloader.bat' })
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
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("Media Downloader")]
[assembly: AssemblyProduct("Media Downloader")]
[assembly: AssemblyCompany("Andreas-Pinheiro")]
[assembly: AssemblyCopyright("by Andreas-Pinheiro")]
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
            if (Setup.IsSetupMode(args)) { Setup.Run(args); return; }
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
            if (File.Exists(Path.Combine(bin, "installed.txt"))) psi.EnvironmentVariables["YTDL_INSTALLED"] = "1";
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
            tray.Text = "Media Downloader - by Andreas-Pinheiro";
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
                string d = null;
                try
                {
                    string sj = File.ReadAllText(Path.Combine(bin, "settings.json"));
                    Match m = Regex.Match(sj, "\"dlDir\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
                    if (m.Success) d = m.Groups[1].Value.Replace("\\\\", "\\").Trim();
                }
                catch (Exception) { }
                if (string.IsNullOrEmpty(d))
                {
                    if (File.Exists(Path.Combine(bin, "installed.txt"))) { string up = Environment.GetEnvironmentVariable("USERPROFILE"); if (up == null) up = dir; d = Path.Combine(up, @"Downloads\Media Downloader"); }
                    else d = Path.Combine(dir, "Downloads");
                }
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
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Media Downloader")]
[assembly: AssemblyProduct("Media Downloader")]
[assembly: AssemblyCompany("Andreas-Pinheiro")]
[assembly: AssemblyCopyright("by Andreas-Pinheiro")]
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
            if (Setup.IsSetupMode(args)) { Setup.Run(args); return; }
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
            if (File.Exists(Path.Combine(bin, "installed.txt"))) psi.EnvironmentVariables["YTDL_INSTALLED"] = "1";
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
            tray.Text = "Media Downloader - by Andreas-Pinheiro";
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
                string d = null;
                try
                {
                    string sj = File.ReadAllText(Path.Combine(bin, "settings.json"));
                    Match m = Regex.Match(sj, "\"dlDir\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
                    if (m.Success) d = m.Groups[1].Value.Replace("\\\\", "\\").Trim();
                }
                catch (Exception) { }
                if (string.IsNullOrEmpty(d))
                {
                    if (File.Exists(Path.Combine(bin, "installed.txt"))) { string up = Environment.GetEnvironmentVariable("USERPROFILE"); if (up == null) up = dir; d = Path.Combine(up, @"Downloads\Media Downloader"); }
                    else d = Path.Combine(dir, "Downloads");
                }
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
$setupCs=@'
using System;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Net;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace MediaDownloaderLauncher
{
    static class Setup
    {
        const string UKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\MediaDownloader";
        const string ExeName = "Media-Downloader.exe";
        const string RtGuid = "{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}";
        static bool pt;

        static string T(string p, string e) { return pt ? p : e; }

        public static bool IsSetupMode(string[] args)
        {
            foreach (string a in args) { if (a == "--setup" || a == "--uninstall") return true; }
            string n = Path.GetFileNameWithoutExtension(Application.ExecutablePath);
            return n.IndexOf("setup", StringComparison.OrdinalIgnoreCase) >= 0;
        }

        public static void Run(string[] args)
        {
            pt = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "pt";
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            bool un = false;
            foreach (string a in args) { if (a == "--uninstall") un = true; }
            if (un) Uninstall(); else Wizard();
        }

        static bool RtOk()
        {
            string[] subs = { @"SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\" + RtGuid, @"SOFTWARE\Microsoft\EdgeUpdate\Clients\" + RtGuid };
            RegistryKey[] roots = { Registry.LocalMachine, Registry.CurrentUser };
            foreach (RegistryKey root in roots)
            {
                foreach (string s in subs)
                {
                    try
                    {
                        using (RegistryKey k = root.OpenSubKey(s))
                        {
                            if (k == null) continue;
                            object v = k.GetValue("pv");
                            if (v != null && v.ToString() != "" && v.ToString() != "0.0.0.0") return true;
                        }
                    }
                    catch (Exception) { }
                }
            }
            return false;
        }

        static void KillOthers()
        {
            int me = Process.GetCurrentProcess().Id;
            foreach (Process p in Process.GetProcessesByName("Media-Downloader"))
            {
                if (p.Id == me) continue;
                try
                {
                    ProcessStartInfo k = new ProcessStartInfo("taskkill", "/PID " + p.Id + " /T /F");
                    k.CreateNoWindow = true;
                    k.UseShellExecute = false;
                    Process kp = Process.Start(k);
                    if (kp != null) kp.WaitForExit(5000);
                }
                catch (Exception) { }
            }
        }

        static void MakeLnk(string path, string exe, string wd)
        {
            Type t = Type.GetTypeFromProgID("WScript.Shell");
            object sh = Activator.CreateInstance(t);
            object l = t.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, sh, new object[] { path });
            Type lt = l.GetType();
            lt.InvokeMember("TargetPath", BindingFlags.SetProperty, null, l, new object[] { exe });
            lt.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, l, new object[] { wd });
            lt.InvokeMember("IconLocation", BindingFlags.SetProperty, null, l, new object[] { exe + ",0" });
            lt.InvokeMember("Description", BindingFlags.SetProperty, null, l, new object[] { "Media Downloader - by Andreas-Pinheiro" });
            lt.InvokeMember("Save", BindingFlags.InvokeMethod, null, l, null);
        }

        static string Desktop() { return Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory); }
        static string StartMenu() { return Environment.GetFolderPath(Environment.SpecialFolder.Programs); }

        static string DoInstall(string target, bool desk, bool menu, Action<string> say)
        {
            try
            {
                say(T("Verificando o WebView2...", "Checking WebView2..."));
                if (!RtOk())
                {
                    DialogResult r = MessageBox.Show(
                        T("O Media Downloader precisa do Microsoft Edge WebView2 Runtime (gratuito, da Microsoft) para abrir em janela própria.\n\nInstalar a última versão agora?",
                          "Media Downloader needs the Microsoft Edge WebView2 Runtime (free, from Microsoft) to open in its own window.\n\nInstall the latest version now?"),
                        "Media Downloader", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
                    if (r == DialogResult.Yes)
                    {
                        say(T("Baixando e instalando o WebView2...", "Downloading and installing WebView2..."));
                        try
                        {
                            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;
                            string tmp = Path.Combine(Path.GetTempPath(), "MicrosoftEdgeWebview2Setup.exe");
                            using (WebClient wc = new WebClient()) { wc.DownloadFile("https://go.microsoft.com/fwlink/p/?LinkId=2124703", tmp); }
                            Process p = Process.Start(tmp, "/silent /install");
                            if (p != null) p.WaitForExit();
                        }
                        catch (Exception) { }
                    }
                }

                say(T("Fechando o programa, se estiver aberto...", "Closing the program if it is open..."));
                KillOthers();

                say(T("Copiando arquivos...", "Copying files..."));
                string bin = Path.Combine(target, "bin");
                Directory.CreateDirectory(target);
                Directory.CreateDirectory(bin);
                string self = Application.ExecutablePath;
                string dst = Path.Combine(target, ExeName);
                if (!string.Equals(Path.GetFullPath(self), Path.GetFullPath(dst), StringComparison.OrdinalIgnoreCase)) File.Copy(self, dst, true);
                File.WriteAllText(Path.Combine(bin, "installed.txt"), "1");
                File.WriteAllText(Path.Combine(bin, "shortcuts.done"), "1");

                say(T("Criando atalhos...", "Creating shortcuts..."));
                string d1 = Path.Combine(Desktop(), "Media Downloader.lnk");
                string d2 = Path.Combine(StartMenu(), "Media Downloader.lnk");
                if (desk) MakeLnk(d1, dst, target); else { try { File.Delete(d1); } catch (Exception) { } }
                if (menu) MakeLnk(d2, dst, target); else { try { File.Delete(d2); } catch (Exception) { } }

                say(T("Registrando em Aplicativos do Windows...", "Registering in Windows Apps..."));
                using (RegistryKey k = Registry.CurrentUser.CreateSubKey(UKey))
                {
                    k.SetValue("DisplayName", "Media Downloader");
                    k.SetValue("DisplayVersion", "2.1");
                    k.SetValue("Publisher", "Andreas-Pinheiro");
                    k.SetValue("InstallLocation", target);
                    k.SetValue("DisplayIcon", dst);
                    k.SetValue("UninstallString", "\"" + dst + "\" --uninstall");
                    k.SetValue("NoModify", 1, RegistryValueKind.DWord);
                    k.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                }
                return null;
            }
            catch (Exception ex) { return ex.Message; }
        }

        static void Launch(string exe)
        {
            try { Process.Start(exe); } catch (Exception) { }
        }

        static Label Lbl(Form f, string text, int x, int y, int w, int h, float size, bool bold, Color c)
        {
            Label l = new Label();
            l.Text = text;
            l.SetBounds(x, y, w, h);
            l.ForeColor = c;
            l.BackColor = Color.Transparent;
            l.Font = new Font("Segoe UI", size, bold ? FontStyle.Bold : FontStyle.Regular);
            f.Controls.Add(l);
            return l;
        }

        static CheckBox Chk(Form f, string text, int y, bool on)
        {
            CheckBox c = new CheckBox();
            c.Text = text;
            c.Checked = on;
            c.SetBounds(28, y, 460, 24);
            c.ForeColor = Color.FromArgb(230, 241, 255);
            c.BackColor = Color.Transparent;
            c.Font = new Font("Segoe UI", 10f);
            f.Controls.Add(c);
            return c;
        }

        static void Wizard()
        {
            string target = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Programs\Media Downloader");
            string exeTarget = Path.Combine(target, ExeName);
            Color fg = Color.FromArgb(230, 241, 255);
            Color mu = Color.FromArgb(143, 160, 201);

            Form f = new Form();
            f.Text = T("Instalar Media Downloader", "Install Media Downloader");
            f.FormBorderStyle = FormBorderStyle.FixedDialog;
            f.MaximizeBox = false;
            f.MinimizeBox = false;
            f.StartPosition = FormStartPosition.CenterScreen;
            f.ClientSize = new Size(520, 400);
            f.BackColor = Color.FromArgb(14, 20, 40);
            f.ForeColor = fg;
            try { f.Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch (Exception) { }

            PictureBox pb = new PictureBox();
            pb.SetBounds(26, 22, 72, 72);
            pb.SizeMode = PictureBoxSizeMode.Zoom;
            pb.BackColor = Color.Transparent;
            try { if (f.Icon != null) { using (Icon ic = new Icon(f.Icon, 64, 64)) { pb.Image = ic.ToBitmap(); } } } catch (Exception) { }
            f.Controls.Add(pb);

            Lbl(f, "Media Downloader", 108, 26, 390, 36, 18f, true, fg);
            Lbl(f, "by Andreas-Pinheiro", 110, 64, 390, 22, 9f, false, mu);
            Lbl(f, T("Este assistente instala o programa neste computador, cria os atalhos e verifica o WebView2 (a janela do app).",
                     "This wizard installs the program on this computer, creates the shortcuts and checks WebView2 (the app window)."), 28, 110, 470, 44, 10f, false, fg);
            Lbl(f, T("Pasta de instalação:", "Install folder:"), 28, 160, 470, 20, 9f, false, mu);
            Lbl(f, target, 28, 180, 470, 22, 9.5f, false, fg);

            CheckBox cbDesk = Chk(f, T("Criar atalho na Área de Trabalho", "Create a Desktop shortcut"), 214, true);
            CheckBox cbMenu = Chk(f, T("Criar atalho no Menu Iniciar", "Create a Start Menu shortcut"), 242, true);
            CheckBox cbRun = Chk(f, T("Abrir o Media Downloader ao terminar", "Open Media Downloader when finished"), 270, true);

            Label status = Lbl(f, "", 28, 312, 470, 22, 9.5f, false, mu);
            ProgressBar bar = new ProgressBar();
            bar.SetBounds(28, 338, 464, 12);
            bar.Style = ProgressBarStyle.Continuous;
            f.Controls.Add(bar);

            Button btn = new Button();
            btn.Text = T("Instalar", "Install");
            btn.SetBounds(392, 360, 100, 30);
            f.Controls.Add(btn);
            Button cancel = new Button();
            cancel.Text = T("Cancelar", "Cancel");
            cancel.SetBounds(286, 360, 100, 30);
            cancel.Click += delegate { f.Close(); };
            f.Controls.Add(cancel);

            bool done = false;
            bool running = false;
            btn.Click += delegate
            {
                if (done)
                {
                    if (cbRun.Checked) Launch(exeTarget);
                    f.Close();
                    return;
                }
                if (running) return;
                running = true;
                btn.Enabled = false;
                cancel.Enabled = false;
                cbDesk.Enabled = false; cbMenu.Enabled = false; cbRun.Enabled = false;
                bar.Style = ProgressBarStyle.Marquee;
                bool dsk = cbDesk.Checked, mn = cbMenu.Checked;
                Thread th = new Thread(delegate()
                {
                    string err = DoInstall(target, dsk, mn, delegate(string s)
                    {
                        try { f.BeginInvoke(new MethodInvoker(delegate { status.Text = s; })); } catch (Exception) { }
                    });
                    try
                    {
                        f.BeginInvoke(new MethodInvoker(delegate
                        {
                            bar.Style = ProgressBarStyle.Continuous;
                            running = false;
                            btn.Enabled = true;
                            if (err == null)
                            {
                                bar.Value = 100;
                                status.ForeColor = Color.FromArgb(94, 234, 212);
                                status.Text = T("Pronto! O Media Downloader foi instalado.", "Done! Media Downloader is installed.");
                                btn.Text = T("Concluir", "Finish");
                                done = true;
                            }
                            else
                            {
                                bar.Value = 0;
                                status.ForeColor = Color.FromArgb(251, 113, 133);
                                status.Text = T("Não deu certo: ", "Failed: ") + err;
                                btn.Text = T("Fechar", "Close");
                                cbRun.Checked = false;
                                done = true;
                            }
                        }));
                    }
                    catch (Exception) { }
                });
                th.IsBackground = true;
                th.Start();
            };
            Application.Run(f);
        }

        static void Uninstall()
        {
            string exe = Application.ExecutablePath;
            string dir = Path.GetDirectoryName(exe);
            if (MessageBox.Show(
                T("Remover o Media Downloader deste computador?\n\nSeus downloads não serão apagados.",
                  "Remove Media Downloader from this computer?\n\nYour downloads will not be deleted."),
                "Media Downloader", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            KillOthers();
            try { File.Delete(Path.Combine(Desktop(), "Media Downloader.lnk")); } catch (Exception) { }
            try { File.Delete(Path.Combine(StartMenu(), "Media Downloader.lnk")); } catch (Exception) { }
            try { Registry.CurrentUser.DeleteSubKeyTree(UKey, false); } catch (Exception) { }
            try
            {
                // so apaga os arquivos do proprio programa (nunca a pasta inteira) depois que este processo terminar
                ProcessStartInfo p = new ProcessStartInfo("cmd.exe",
                    "/c ping 127.0.0.1 -n 3 >nul & rmdir /s /q \"" + Path.Combine(dir, "bin") + "\" & del /f /q \"" + exe + "\" & rmdir \"" + dir + "\"");
                p.CreateNoWindow = true;
                p.UseShellExecute = false;
                Process.Start(p);
            }
            catch (Exception) { }
            MessageBox.Show(T("Removido.", "Removed."), "Media Downloader");
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
$exeSb={ param($S,$lib,$cs,$csBasic,$setupCs)
 . ([scriptblock]::Create($lib))
 try{
  $dir=$S.dir; $exe=J $dir 'Media-Downloader.exe'; $stamp=J $S.bin 'exe.stamp'
  $hash=Md5 ($S.payload+$cs+$csBasic+$setupCs); $setupExe=J $dir 'Media-Downloader-Setup.exe'
  if((Test-Path $exe) -and (Test-Path $stamp) -and ((Get-Content $stamp -Raw).Trim() -eq $hash)){ $S.exeok=$true; if(-not(Test-Path $setupExe)){ try{ Copy-Item $exe $setupExe -Force }catch{} }; [void](Make-Shortcuts $true); return }
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
   $res=$prov.CompileAssemblyFromSource($cp,[string[]]@($src,$setupCs))
   if(-not $res.Errors.HasErrors){ $built=$true; if($tier -eq 2){ L (Tr '(.exe gerado sem a janela WebView2: o codigo dela nao compilou neste Windows; usando Edge/Chrome)' '(.exe built without the WebView2 window: its code did not compile on this Windows; using Edge/Chrome)') }; break }
   $k=0; foreach($e in $res.Errors){ if($k -lt 3){ L "(exe tier $tier) $e" }; $k++ } }
  if(-not $built){ return }
  try{ Copy-Item $out $exe -Force; try{ Copy-Item $out $setupExe -Force }catch{}; Set-Content $stamp $hash; $S.exeok=$true; L (Tr "Gerei/atualizei o Media-Downloader.exe ao lado deste arquivo." "Created/updated Media-Downloader.exe next to this file."); [void](Make-Shortcuts $true) }
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
body{margin:0;font:1rem/1.45 system-ui,-apple-system,"Segoe UI",sans-serif;background:var(--bg);color:var(--fg);height:100vh;height:100dvh;overflow:hidden}
.wrap{max-width:1500px;margin:0 auto;padding:12px 16px 0;height:100%;display:flex;flex-direction:column}
#main{flex:1;min-height:0;display:flex;flex-direction:column;overflow-y:auto;overflow-x:hidden;padding-right:4px;scrollbar-width:thin;scrollbar-color:var(--line) transparent}
#main::-webkit-scrollbar{width:8px}#main::-webkit-scrollbar-thumb{background:var(--line);border-radius:8px}
#main>.card,#main>details{flex:none}#main>.pane.on{flex:1 1 auto;min-height:0}#main>#p_cfg.on{flex:none}#p_pick.on{display:flex;flex-direction:column;min-height:400px}#p_pick.on>.card{flex:1;display:flex;flex-direction:column;min-height:0;margin-bottom:0}#p_pick .tw{flex:1;min-height:90px;max-height:none}#p_links.on{display:flex;flex-direction:column;min-height:150px}#p_links .card{flex:1;display:flex;flex-direction:column;margin-bottom:0}#p_links textarea{flex:1;resize:none;min-height:70px}
@media(min-width:900px){#p_cfg.on{display:grid;grid-template-columns:repeat(auto-fit,minmax(380px,1fr));gap:0 var(--gap)}}
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
#bar{flex:none;margin:0 -16px;background:var(--card);border-top:1px solid var(--line);box-shadow:0 -6px 20px rgba(0,0,0,.12);padding:10px 16px;z-index:5}
#bar .in{max-width:1500px;margin:0 auto;display:flex;gap:12px;align-items:center;flex-wrap:wrap}
#bar .st{flex:1;min-width:200px}#bar .st b{display:block;font-size:.95rem;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
#cur{color:var(--mu);font-size:.8rem;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.sw{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.sw button{width:30px;height:30px;padding:0;border-radius:50%;border:2px solid var(--card);box-shadow:0 0 0 1px var(--line)}
.sw button.on{box-shadow:0 0 0 2px var(--fg)}
.sw input[type=color]{width:36px;height:30px;padding:0;border:0;background:none}
hr{border:0;border-top:1px solid var(--line);margin:12px 0}
footer{flex:none;margin:4px 0 6px;text-align:center;color:var(--mu);font-size:.75rem}footer a{color:inherit}
.hide{display:none!important}
body:not([data-tab=cfg]) #dt:not(.has){display:none}body:not([data-tab=cfg]) #donate{display:none!important}
@media(max-width:560px){.row>*{min-width:100%}#bar .in{gap:8px}}
</style></head><body data-tab="links"><div class="wrap">
<header><img id="logo" alt=""><div><h1>Media Downloader</h1><div class="by">by Andreas-Pinheiro</div></div><div class="sp"></div>
<label class="fld nf" style="min-width:0"><span data-t="lang"></span><select id="lang"><option value="en">English</option><option value="pt">Português</option></select></label>
<button id="qbtn" class="s nf" onclick="if(confirm(t('quit_q')))api('quit',{})" data-t="quit"></button></header>
<div class="sub"><span data-t="sub"></span> <span id="ver"></span></div>
<div id="banner"></div>

<div class="tabs"><button id="t_links" class="on" onclick="tab('links')" data-t="t_links"></button><button id="t_pick" onclick="tab('pick')" data-t="t_pick"></button><button id="t_cfg" onclick="tab('cfg')" data-t="t_cfg"></button></div>

<div id="main">
<div id="p_links" class="pane on">
<div class="card"><h2><span class="n">1</span><span data-t="s1_links"></span></h2>
<textarea id="urls" data-ph="urlsph"></textarea>
<div class="row" style="margin-top:8px;align-items:center"><button class="s nf k-search" onclick="chk()" data-t="chk"></button><span id="ck" class="mu"></span></div></div>
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
<label class="fld"><span data-t="corner"></span><select id="corner"><option value="round" data-t="c_round"></option><option value="square" data-t="c_square"></option></select></label>
<label class="fld"><span data-t="cursor"></span><select id="curmode"><option value="default" data-t="cur_def"></option><option value="pack" selected data-t="cur_girl"></option><option value="custom" data-t="cur_custom"></option></select></label></div>
<div class="row hide" id="cursz" style="margin-top:8px"><label class="fld" style="max-width:260px"><span data-t="cur_size"></span><select id="curpx2"><option value="24" data-t="cs_xs"></option><option value="32" selected data-t="cs_s"></option><option value="48" data-t="cs_m"></option><option value="64" data-t="cs_l"></option></select></label></div>
<div class="row hide" id="curpick" style="margin-top:8px;align-items:center"><button class="s nf" onclick="$('curfile').click()" data-t="cur_pick"></button><input type="file" id="curfile" accept="image/png,image/jpeg,image/webp,image/gif" class="hide"><span class="mu" data-t="cur_note"></span></div>
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
<div class="row" style="margin-top:10px"><button class="s nf k-reload" onclick="upd()" data-t="updall"></button></div>
<div class="mu" style="margin-top:6px" data-t="updnote"></div></div>
</div>

<div class="card" id="donate" style="display:none;text-align:center"><div style="font-weight:600" data-t="don_t"></div><div class="row" id="donl" style="justify-content:center;margin-top:10px"></div></div>
<details id="dt" class="card"><summary data-t="details"></summary><div id="cur2" class="mu"></div><pre id="log"></pre><div id="alts"></div><div id="fails"></div></details>
</div>
<footer>Media Downloader · by <a href="https://github.com/Andreas-Pinheiro" target="_blank" rel="noopener">Andreas-Pinheiro</a></footer>

<div id="bar"><div class="in"><div class="st"><b id="stline"></b><progress id="bar2" max="100" value="0"></progress><div id="cur"></div></div>
<button id="go" class="big" onclick="go()"></button><button id="stopb" class="s" onclick="api('stop',{})" data-t="stop"></button><button class="s k-open" onclick="api('open',{what:'dl'})" data-t="openfolder"></button></div></div>
</div>
<script>
const T='__TOK__',$=i=>document.getElementById(i);
const D={"pt": {"lang": "Idioma", "quit": "Sair", "quit_q": "Encerrar o programa?", "sub": "Baixe músicas e vídeos de mais de mil sites, só colando o link.", "t_links": "Baixar", "t_pick": "Playlist", "t_cfg": "Configurações", "s1_links": "Cole o link", "s1_pick": "Carregue a playlist", "s2": "Escolha o que você quer", "urlsph": "Cole aqui um ou mais links (um por linha). Pode ser vídeo, música ou playlist, de qualquer site.", "chk": "Verificar link", "ka": "Música (só áudio)", "kv": "Vídeo", "afmt": "Formato da música", "f_mp3": "MP3 (funciona em tudo)", "f_m4a": "M4A (boa qualidade)", "f_flac": "FLAC (sem perdas)", "f_wav": "WAV (sem compressão)", "aq": "Qualidade do áudio", "q_best": "Melhor", "q_high": "Alta (320 kbps)", "q_mid": "Média (192 kbps)", "q_low": "Menor arquivo (128 kbps)", "vq": "Qualidade do vídeo", "vcont": "Formato do vídeo", "mp4o": "MP4 (funciona em tudo)", "mkvo": "MKV (original, sem converter)", "qnote": "Dica: muitos sites oferecem áudio de cerca de 128–160 kbps, então qualidades maiores podem não melhorar o som.", "more": "Mais opções (pastas, numeração, intervalo...)", "plm": "Onde guardar playlists e canais", "plm1": "Numa pasta com o nome da playlist (retoma se já existir)", "plm2": "Numa pasta nova a cada vez (nome + data e hora)", "plm3": "Sem pasta (tudo solto)", "num": "Numerar os arquivos pela ordem da playlist", "batch": "Ao colar vários links, guardar tudo numa pasta \"Lote data-hora\"", "split": "Separar em subpastas Músicas e Vídeos", "from": "Começar no item", "to": "Parar no item", "all": "todos", "nopl": "Baixar só o vídeo do link (ignorar a playlist)", "plph": "Link da playlist, álbum ou canal", "plload": "Carregar lista", "stop": "Parar", "plhint": "Cole o link e clique em Carregar lista. Depois marque as faixas e escolha áudio ou vídeo.", "selall": "Marcar todos", "selnone": "Desmarcar", "selinv": "Inverter", "filt": "Filtrar por título ou canal", "as": "Baixar como:", "pm_a": "Tudo em áudio", "pm_v": "Tudo em vídeo", "pm_m": "Misturado (escolho em cada faixa)", "th_title": "Título", "th_ch": "Canal", "th_dur": "Duração", "th_type": "Tipo", "h_look": "Aparência", "theme": "Tema", "th_auto": "Automático (segue o Windows)", "th_light": "Claro", "th_dark": "Escuro", "th_neon": "Neon", "fsize": "Tamanho do texto", "fs_s": "Pequeno", "fs_m": "Normal", "fs_l": "Grande", "fs_xl": "Muito grande", "dens": "Espaçamento", "d_comfy": "Confortável", "d_compact": "Compacto", "cursor": "Cursor do mouse", "cur_def": "Padrão", "cur_girl": "Menina gato neon (pacote completo)", "cur_size": "Tamanho do cursor", "cs_xs": "Muito pequeno", "cs_s": "Pequeno", "cs_m": "Médio", "cs_l": "Grande", "cur_custom": "Minha própria imagem", "cur_pick": "Escolher imagem...", "cur_note": "Use uma imagem sua ou que você tenha permissão para usar. Ela fica salva só neste computador.", "corner": "Cantos", "c_round": "Arredondados", "c_square": "Retos", "accent": "Cor de destaque", "reset_look": "Restaurar aparência", "h_where": "Arquivos e abertura", "dldir": "Pasta de downloads (vazio = a pasta Downloads ao lado do programa)", "openm": "Como abrir o programa (vale na próxima vez que abrir)", "openm_a": "Janela própria (WebView2 embutido no .exe; sem ele, Edge/Chrome em modo aplicativo)", "openm_b": "Aba do navegador padrão", "shortc": "Criar atalhos (Área de Trabalho e Menu Iniciar)", "openbin": "Abrir pasta do programa", "h_behav": "Comportamento", "meta": "Colocar capa e informações (artista, título) no arquivo", "safe": "Modo cuidadoso: faz pausas entre os downloads para evitar bloqueio", "alt": "Se um vídeo estiver bloqueado ou removido, procurar uma versão alternativa", "addid": "Colocar o ID do vídeo no nome do arquivo", "reset": "Começar do zero (ignorar o histórico do que já foi baixado)", "selfupd": "Verificar e baixar atualizações do próprio programa ao abrir (vale na próxima abertura)", "h_acc": "Contas e cookies (só se precisar)", "accnote": "Serve para vídeos privados, com restrição de idade ou quando um site pede login. O programa usa o login do seu navegador, tentando um por vez nesta ordem.", "nock": "Tentar sem cookies primeiro", "wait": "Se todos falharem, esperar quantos minutos antes de tentar de novo? (0 = parar)", "cknote": "Se existir um cookies.txt ao lado do programa, ele é usado primeiro. Navegadores baseados em Chrome podem exigir que estejam fechados; o Firefox é o mais estável.", "don_t": "☕ Doe um café e ajude o desenvolvedor a ficar acordado a noite toda!", "h_upd": "Atualizações", "chan": "Canal de atualização do yt-dlp", "chan_s": "Estável", "chan_n": "Nightly (recebe correções mais rápido)", "updall": "Atualizar tudo agora", "updnote": "O yt-dlp, o ffmpeg e o deno são comparados com a versão mais recente toda vez que o programa abre (e a cada 6 horas se ficar aberto) e atualizados sozinhos quando há novidade. Se um download falhar por extrator desatualizado, o yt-dlp é atualizado e o link é tentado de novo automaticamente. O botão abaixo força a verificação agora.", "details": "Ver detalhes do andamento", "openfolder": "Abrir pasta", "go": "Baixar", "go_pick": "Baixar selecionados", "idle": "Pronto para baixar", "a_pick": "Carregue uma playlist e marque pelo menos uma faixa.", "a_links": "Cole ao menos um link.", "ck_ing": "Verificando...", "ck_err": "Não consegui ler o link: ", "ck_cnt": " item(ns)", "ck_slow": "Demorou demais.", "pl_need": "Cole o link da playlist.", "pl_load": "Carregando a lista...", "pl_fail": "Não consegui carregar: ", "pl_loading": "Carregando... ", "pl_tracks": " faixa(s) · ", "pl_marked": " marcada(s) (", "pl_audio": " áudio, ", "pl_video": " vídeo)", "unavail": "indisponível", "opt_a": "Áudio", "opt_v": "Vídeo", "closed": "Programa encerrado.", "cookies": "cookies: ", "item": "item ", "nocookie": "sem cookies", "ok": "ok", "miss": "falta", "fails": "Não foi possível baixar:\n", "alts": "Versões alternativas baixadas:\n", "noff": "Atenção: o ffmpeg não está instalado (o download falhou). A conversão para MP3/MP4 pode falhar. Vá em Configurações > Atualizar tudo agora para tentar de novo."}, "en": {"lang": "Language", "quit": "Quit", "quit_q": "Quit the program?", "sub": "Download music and videos from over a thousand sites, just by pasting the link.", "t_links": "Download", "t_pick": "Playlist", "t_cfg": "Settings", "s1_links": "Paste the link", "s1_pick": "Load the playlist", "s2": "Choose what you want", "urlsph": "Paste one or more links here (one per line). Video, song or playlist, from any site.", "chk": "Check link", "ka": "Music (audio only)", "kv": "Video", "afmt": "Music format", "f_mp3": "MP3 (works everywhere)", "f_m4a": "M4A (good quality)", "f_flac": "FLAC (lossless)", "f_wav": "WAV (uncompressed)", "aq": "Audio quality", "q_best": "Best", "q_high": "High (320 kbps)", "q_mid": "Medium (192 kbps)", "q_low": "Smallest file (128 kbps)", "vq": "Video quality", "vcont": "Video format", "mp4o": "MP4 (works everywhere)", "mkvo": "MKV (original, no conversion)", "qnote": "Tip: many sites offer audio of around 128–160 kbps, so higher qualities may not improve the sound.", "more": "More options (folders, numbering, range...)", "plm": "Where to keep playlists and channels", "plm1": "In a folder named after the playlist (resumes if it exists)", "plm2": "In a new folder every time (name + date and time)", "plm3": "No folder (everything loose)", "num": "Number the files in playlist order", "batch": "When pasting several links, keep everything in a \"Batch date-time\" folder", "split": "Split into Music and Videos subfolders", "from": "Start at item", "to": "Stop at item", "all": "all", "nopl": "Download only the video in the link (ignore the playlist)", "plph": "Playlist, album or channel link", "plload": "Load list", "stop": "Stop", "plhint": "Paste the link and click Load list. Then tick the tracks and choose audio or video.", "selall": "Select all", "selnone": "Select none", "selinv": "Invert", "filt": "Filter by title or channel", "as": "Download as:", "pm_a": "All as audio", "pm_v": "All as video", "pm_m": "Mixed (I choose per track)", "th_title": "Title", "th_ch": "Channel", "th_dur": "Length", "th_type": "Type", "h_look": "Appearance", "theme": "Theme", "th_auto": "Automatic (follows Windows)", "th_light": "Light", "th_dark": "Dark", "th_neon": "Neon", "fsize": "Text size", "fs_s": "Small", "fs_m": "Normal", "fs_l": "Large", "fs_xl": "Extra large", "dens": "Spacing", "d_comfy": "Comfortable", "d_compact": "Compact", "cursor": "Mouse cursor", "cur_def": "Default", "cur_girl": "Neon cat girl (full pack)", "cur_size": "Cursor size", "cs_xs": "Very small", "cs_s": "Small", "cs_m": "Medium", "cs_l": "Large", "cur_custom": "My own image", "cur_pick": "Choose image...", "cur_note": "Use your own image or one you have permission to use. It stays only on this computer.", "corner": "Corners", "c_round": "Rounded", "c_square": "Square", "accent": "Accent color", "reset_look": "Reset appearance", "h_where": "Files and opening", "dldir": "Downloads folder (empty = the Downloads folder next to the program)", "openm": "How to open the program (applies the next time it opens)", "openm_a": "Own window (WebView2 built into the .exe; without it, Edge/Chrome in app mode)", "openm_b": "Default browser tab", "shortc": "Create shortcuts (Desktop and Start Menu)", "openbin": "Open program folder", "h_behav": "Behavior", "meta": "Put cover art and info (artist, title) in the file", "safe": "Careful mode: pauses between downloads to avoid being blocked", "alt": "If a video is blocked or removed, look for an alternative version", "addid": "Put the video ID in the file name", "reset": "Start over (ignore the history of what was already downloaded)", "selfupd": "Check for and download updates of the program itself when it opens (applies on next opening)", "h_acc": "Accounts and cookies (only if needed)", "accnote": "For private or age-restricted videos, or when a site asks you to sign in. The program borrows the login from your browser, trying one at a time in this order.", "nock": "Try without cookies first", "wait": "If all fail, how many minutes to wait before trying again? (0 = stop)", "cknote": "If a cookies.txt sits next to the program, it is used first. Chrome-based browsers may need to be closed; Firefox is the most stable.", "don_t": "☕ Buy me a coffee and help the developer stay up all night!", "h_upd": "Updates", "chan": "yt-dlp update channel", "chan_s": "Stable", "chan_n": "Nightly (gets fixes sooner)", "updall": "Update everything now", "updnote": "yt-dlp, ffmpeg and deno are compared with the latest version every time the program opens (and every 6 hours while it stays open) and updated by themselves when there is a newer one. If a download fails because of an outdated extractor, yt-dlp is updated and the link is retried automatically. The button below forces a check now.", "details": "Show progress details", "openfolder": "Open folder", "go": "Download", "go_pick": "Download selected", "idle": "Ready to download", "a_pick": "Load a playlist and tick at least one track.", "a_links": "Paste at least one link.", "ck_ing": "Checking...", "ck_err": "Could not read the link: ", "ck_cnt": " item(s)", "ck_slow": "Took too long.", "pl_need": "Paste the playlist link.", "pl_load": "Loading the list...", "pl_fail": "Could not load: ", "pl_loading": "Loading... ", "pl_tracks": " track(s) · ", "pl_marked": " selected (", "pl_audio": " audio, ", "pl_video": " video)", "unavail": "unavailable", "opt_a": "Audio", "opt_v": "Video", "closed": "Program closed.", "cookies": "cookies: ", "item": "item ", "nocookie": "no cookies", "ok": "ok", "miss": "missing", "fails": "Could not download:\n", "alts": "Alternative versions downloaded:\n", "noff": "Warning: ffmpeg is not installed (the download failed). Converting to MP3/MP4 may fail. Go to Settings > Update everything now to try again."}};
const LOGO='data:image/png;base64,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';$('logo').src=LOGO;$('fav').href=LOGO;
let LANG='en';
const t=k=>(D[LANG]&&D[LANG][k])||D.en[k]||k;
const api=(p,b)=>fetch('/api/'+p+(p.indexOf('?')<0?'?':'&')+'t='+T,b?{method:'POST',body:JSON.stringify(b)}:{}).then(r=>r.json());
const esc=s=>String(s==null?'':s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
let cur='links',P={items:[],from:0,busy:false,title:'',url:''},ready=false,running=false,lastStatus=null;
const IDS=['selfUpd','lang','openMode','theme','accent','fsize','density','corner','afmt','aq','vq','vcont','plmode','num','batch','splitType','st','en','noPl','nock','wait','meta','safe','reset','alt','addId','dlDir','chan','curmode','curpx2'];
const FS={s:14,m:16,l:18,xl:20};
function scl(){return Math.max(.85,Math.min(1.7,Math.min(innerWidth/1000,innerHeight/760)))}
window.addEventListener('resize',function(){try{applyLook()}catch(e){}});
function applyLook(){const h=document.documentElement,th=$('theme').value;
if(th==='auto')h.removeAttribute('data-theme');else h.setAttribute('data-theme',th);
h.style.fontSize=((FS[$('fsize').value]||16)*scl())+'px';
if($('density').value==='compact')h.setAttribute('data-dens','compact');else h.removeAttribute('data-dens');
applyCursor();if($('corner').value==='square')h.setAttribute('data-corner','square');else h.removeAttribute('data-corner');
const c=$('accent').value||'#0e7490';h.style.setProperty('--ac',c);
const n=parseInt(c.slice(1),16),r=n>>16,g=(n>>8)&255,b=n&255,L=(0.299*r+0.587*g+0.114*b);h.style.setProperty('--acfg',L>150?'#111':'#fff');
document.querySelectorAll('#sw button[data-c]').forEach(x=>{x.style.background=x.dataset.c;x.classList.toggle('on',x.dataset.c.toLowerCase()===c.toLowerCase())})}
function resetLook(){$('theme').value='auto';$('fsize').value='m';$('density').value='comfy';$('corner').value='round';$('curmode').value='pack';$('curpx2').value='32';$('accent').value='#0e7490';applyLook();save()}
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
function tab(k){cur=k;document.body.dataset.tab=k;for(const x of['links','pick','cfg']){$('p_'+x).classList.toggle('on',x===k);$('t_'+x).classList.toggle('on',x===k)}
$('s2').classList.toggle('hide',k==='cfg');$('go').textContent=k==='pick'?t('go_pick'):t('go');updFmt()}
function common(){const o={};for(const i of IDS){const e=$(i);o[i]=e.type==='checkbox'?e.checked:e.value}
o.browsers=[...document.querySelectorAll('.br:checked')].map(e=>e.value);o.kind=radio('kind');o.pm=radio('pm');o.plurl=$('plurl').value;return o}
let sv=null;function save(){clearTimeout(sv);sv=setTimeout(()=>api('settings',common()),400)}
async function load(){try{const s=await api('settings');for(const i of IDS){if(!(i in s))continue;const e=$(i);if(e.type==='checkbox')e.checked=!!s[i];else e.value=s[i]}
if(s.browsers)document.querySelectorAll('.br').forEach(e=>e.checked=s.browsers.indexOf(e.value)>=0);if(s.kind)setRadio('kind',s.kind);if(s.pm)setRadio('pm',s.pm);if(s.plurl)$('plurl').value=s.plurl}catch(e){}
LANG=$('lang').value||'en';if(!D[LANG])LANG='en';$('lang').value=LANG;applyLook();applyLang();updFmt();
document.querySelectorAll('input,select').forEach(e=>{e.addEventListener('change',save);if(e.type==='color')e.addEventListener('input',()=>{applyLook();save()})});
['theme','fsize','density','corner','curmode','curpx2'].forEach(i=>$(i).addEventListener('change',applyLook));
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
$('dt').classList.toggle('has',!!(s.fails.length||s.alts.length));if(s.fails.length||s.alts.length)$('dt').open=true;
$('go').disabled=s.running||!s.ready;$('stopb').disabled=!s.running}
async function poll(){try{const s=await api('status');running=s.running;ready=s.ready;lastStatus=s;showStatus(s)}catch(e){$('stline').textContent=t('closed')}}
$('tb').addEventListener('change',()=>{});
load();setInterval(poll,1000);poll();

(function(){ if(window.chrome&&window.chrome.webview) return; var tm; function sv(){ clearTimeout(tm); tm=setTimeout(function(){ try{ api('winsize',{x:window.screenX,y:window.screenY,w:window.outerWidth,h:window.outerHeight}) }catch(e){} },700) } window.addEventListener('resize',sv); })();

(function(){ var D=[]; var box=$('donl'); if(D&&D.length){ D.forEach(function(d){ var b=document.createElement('button'); b.className='s'; b.textContent='\u2615 '+d.name; b.onclick=function(){ api('openurl',{url:d.url}) }; box.appendChild(b) }); $('donate').style.display='' }
 document.addEventListener('click',function(e){ var a=e.target.closest&&e.target.closest('a[target=_blank]'); if(a&&/^https:\/\//.test(a.href)){ e.preventDefault(); api('openurl',{url:a.href}) } }) })();

var CUR={"busy":["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",24,71,96,91],"click":["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",2,2,93,96],"close":["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",77,57,96,69],"context":["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",81,57,96,69],"copy":["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",58,68,96,91],"help":["iVBORw0KGgoAAAANSUhEUgAAAF4AAABgCAMAAACjfDWBAAABgFBMVEUMmOBcGplXG2YcHZjfmN+hE98LFaVh5PsLXaEn3fif6fsQK2GhW5zbHfYHCmgOX+UkDi3SaKwJG8yWJKGgpfcCXN8V1/nT1fQCC09cXuUDo/bmaehmG9RmEshemu////8Fn/EJNMxmUqJa4fYQGZkDYvCXLmeYYejWi7UBWelrR3AEC18iT6wNi64HT3EACTKJHdT/AP8Amf1rCMmSTnAQF5dSCbSNDdqtiLQHzfZmFDcCACcTKs5QI5oFDjsESrBYA7hxCOF/f79fpdzNLr3QUXgAVQAAVVUYVJkA/wB/fwBUkbhRs9aqt/2q//+UwPz/AADALlj/f/8AAAAFBS8BARAICEsPE1AIFm0GCGz71u4DJ436yOgAAP8EF4svFmwHJXAG1/oqFVMDNq4uBm4A//8oB08J5/v55/gLEjYxBo1KBJAENpMDtvMESM32+foEqPIDV7MCZtD1ttsH9v1sBbD4uecGJ6kEVswBd9PxqNQCSK8KdekHx/gHmO7N+fkYho8RAAAAgHRSTlP5/f78/vka/v72/f7/+RLy/f8h/v1Wrv2t/qD+cfn+AWr+/7RcIf///6D/VRv9/wpuARmk/5hjpv9v/3FOGLNkkhYEmf//AwOUAQL/WLcDuQH/AgD+/v7+/v7//v8B/v/+/P/+/gH+/f/+/v7+/P7+/f7+//3+//7+/v/+/vz7/kpIG3wAABGXSURBVHjajZqJf9pIlsdLByAQp8EhtmOP7fiK03Gm00l3JtM9x87M7s7svS6VSoiIQxgMBgzYBnP6X5/3SgJjJ+mkko8DCnz16lev3lEyOb0f8b0/xk+/eXyELwS/9iGyRP9LJPKX4Ol/wzc/fp1+dhpfffL8P78dvxoJhSLZf3+5/y22A309fKKF4r85+0b881BnFrrLak9X3wS/gf6kpBv10va3Wf/xNP48PFRm4cidZr14sSq0/VU6qRsGJU++exP/Jvzr52HCgB+KvLLGiV/l7/t0w9BIkqyenn2j9Sa1JrVwZMtyE6vxz/E/np0hK/icMLCdU71FT9aDX7ZkGR+aMEqtXi18t8XtxIsvfusf8eevKAwt02REN37N/Md4xpAfCX2OHz+Nf7f/Zn/vKdLrbDeb22LaiaGtx79o/gNxeoxaFrNua7VQmDuP+PBy/0UChrK1RQ3KpHyun7GKmlGffdn8e3xQ4BXHYqz7Wf7+yh6vU8MgIdRdUtVDtS+xpmF0t1+ffiPecRxQSPBt5OMG9jbx/p5OhbOEiqB7ZWPjUFXVXdakhv4ifvbxG/E7iiX4pVC46ST2F+bvPzXE0AnSaWAjoF7m1AyzTcOAj519Db/iiQPagjysW5qGQk3rxRv4vzdvVl7u+XSjWzQoNcD4wGEuGwkxm8OE1le+Ks7Kk5rAh4APN3A74Uikab17E1x98TRpzEcR6Iwaa331cG2NXId5sUgNc/wl51zGl24FnkwGFtzAgQAUabJ3ewoTYCqUN9FpDKMgHWYImV5f69ymcD8t/Hn+Mn664+E7xMYFtibIp/4wqLE0AKl1SrXrGuBhL+qGFv75K0v7pNQG/CQy7XSGNqwvZchXBJohHPYc8+Zg4A1Zc0xCJwzxoBghP//97NfFAfxgEglNW52hg0ArEbrMOkiHd3w+D3xj+C//Q6eAZ0W40Plc7Fm2viXwd5HwtDPrwfYyqJWIXEYc5tlOjTnVNM25ZMYcb5itz8j/AO/O8a3ZxLUsYX/mMqv4ghgLPuM29+hzPEa4J8FP+MvitFxK7cTdXag1G94OLGE029kS+gB8WXZq2uAxJl4xOWW2AcvCyPbrr+GdXvYyMpvctgcWUGACFPgZxdPBU8ifQLHpT4BSDnjOrWL4k927jO8g/jZ7HiE9wAvbfX5WmXsnXdzA5K7irTOFnUstp83Jk8eruxwUCGjP21nY6sO2K1yQ4k+6kznPWPd4uF5H8wuWpgk+dcVHnXa39Hh1l0Ma4q12NrMVIm0uvM/ylnMts+Og4As+qM4KFanqFud7gYL63G09WXlo/hL+fwDPLDezthWeueAPQhpvNRXH83dmzEUymSxJFdrG/Mbxsth0zfD26YPYvCTOfyGeAX7Smbkc6QI/9xfGTCG08HuDFipywWLFW7hud3T8FNzH0p4/NH+O//50JZNA/GBtZ+eWDJnBMa7RxQC4Cf6IeJPqdUOXCowVaHfMCLkuYVUCeNtpbX9W+9+c/pxZGwDeXhuAE3RczWbKwl4G+xSsN9HTgWIynRYQryhswoF+/UqEJGo7XVD/7HP4Z6qHT3Bmjd1EgkkNi+Pux7/Ix1uALGVFUUxepDp8uCAx+7ZYKtVKSYFntg3mfwmvwDccBbyT0Wa7IYE6iGciyMCwCszUjbK0CUabtABzgRnRXpHUatcnqA6Ezqb2wPzHeNiBwpWZIimWwguw403q2c2kTYkpsKgK5+KWGAgY1ccngA8jHlamqZHf/RqecYqbnV00IGFZiskU8HGzUCiUwexdCpnVtDg3hW8KPO2ZrRp5JfDUKHa1Zd9fxh8i3tuHRqUibmVSEAKuFAowA0Xh4DoYXnCVDdOjG11d1ym6Di487Q6XnWcZH2h4eNw3FfwqmIPrgAGSQdWnc+E6FBccXd8UH6W6ZhRJieAFyMLmsLWk/iO8l/jgRwW9HPHMw5v1et0U2CS6qedPfnIZ8tY1GSc0+Cx4sT6tbX8BPw+HRqUq0KbIg57jIx3w5bflclVkK8P0p9oF4wcKCRdh1eAL2vV68PSLeBHLLoTlouoQcWbu+NQsRGWfL9RBDTVb6wzaIYJJBTPZNLxQZwm/EbgQkQMWqVIxPOlFjbDAl01aLqSiyXK1XBa+I7yHFsd8NlhbU7pe+LSG1+ufWv9b1cNjCKtWhV0iBHj4Mo6CCWH4UEXz4TUVeFyYW+t2sNVQEmg6XHBLi7TyAC8BysL4WGE+XmSjJKWALoPvA1VS86osy/CGebaDvbec25kG0yDLYAp2ZrV5WnmI97UB6UX8hf3FyjQJc0E24uVqQd2IRuU08pfwlpJZ200gHlISu73ejn9OHF+biuRFYI5zSCarBVoAg2UJflYrUfXoKCVHpYLi7VrEO45yuJaZIH6Hc2rX5iXVEh6WVpSngG+IzcsLIFY5maRlCL+QnAAvVXbz0bept0m8yjEU3VufmYCY9i2UQHbps/iqX8swHw8FgFkFQcq0LImRluSofPDWr8cxquENaJtb9hbUvnAve2LDKM3jzn22eraxOS+DFcW3HuIL5FQZXEXQo2l4cywvVcrCfhBHcUMJMquD55CmbfPW3POXrd+kfiG248zxBSan05KEwsNIHUjRo2PxEUkuS4gXAQK0d8MT0oEIZU26vMnJvCJZwsekql8ZOI6RlDFOUvAVuYrLWgBhUkdy9ChK4V2VViqFQ0xQJtaAbUVxSzNCINpZvSHXPsX/P+AvZL8SBud/qwIf8Z7KYHw6epWSj7JRaUMCO2jFalCIbhwcxRwoShsy7gnixzO7aWsP8R9P//xOCtxcGF5GhiWI9o/QY8pzkWUpPbqKRvN56DahfmKNTZQMKkHAc0dxhlqJ4He527GbxfH0ofXxZxdVKVAR1kN5Q423/VFK9tZCN7Dqk9X+aJTHcS7FYulAIJBOIb4IJQu3HEI0XeAHHc3mY7LsOdDx/9CgAR/PBpwmD/JXI/UAOzVTg7AQrcupfh/hudylmo5tbGykoymZcUhg1KYWH0+J+C53OppldefHDD7+x82qHLjxtecsrR7l+ylVleuGWfRqVlm9ynsjdxlN//Wv6fQoLZsOujAEYouQpPiupRDC2O2DmCPw6YDnOWVKj/u5fP5KvepHQZqtsgQ7X5Zy+fnIjlKplHqlpiWuYNxsmjpp6X5j4XRL3H4RXMbDnrqRA5sXntQ0OQLU6Op8lFLL1Myk04GLw1T0Hj9SR/18/yoVVRQ8ACgWNe1k3hcxu9myyfaDdIL4AEZ7Yb1RTh1dneeyORjgnrsb6VhsIz3KeQPw/SsY/VFUEnTapIteFwO+2+29eJQMg3/ajMHCilxYNqL56OjcY43UYxYNpNNpVZDv+f1+dLfoVXDF+1Ya04Tdra0+SOUovWc84Mtl47ivqoDP50D/0YhWhdKAzl8t7O+ru+gzIhWa93iIaRa3W0/iDyqFf/0hELuBda1iBQJLG1WjV0fq1dUI/sr0OJU6QrfJ3cuTz2d2d6NJoXax7nelosKDbWz37ls4xH//+ieQpmpUcQJQVlNTZ8e0DLFlt//+aLcqR1W1f49H/pWqwqYqCzz18SLTIn7cWc610PcEYlLFMNKIZ5aobPwJ19n7bDmaQldBMCx4XvBVdfTWqFcxyevz8xLEcywR7WZne8kx4z/E0hdVQ4pVsI2q0ns6fu+4IIE2Hh4CTkrwcznYEmW0wzsBE4EK2xMDQgS38fxl38fH/xSDYGlUY5CtqgW/O2Pi3EBYZTnRKy8c5Eajvlje8zxGfYH3FtbHww6DqMlha/kHAERIg25zEQuwiiKqmsLa2tYWmUx6Y1NsdOt4lBeSe755fn6EGYuJZap7ujO/NcTNyx1HK62LoEZOf3kWQ7ehEigkIa1xmIERiYRC4dZszETLmjx+fzX3/PNs9OAA8AXE28biqArxdhffQAvX9bI5Od0TxjMmxW5uqDigzOWy55di3IVKBAtmDrOoH0dVMPw8B/BUFH2Mo/Wm8BxRYAC+2KvjPLg98BIWgXWN3TAouG8CaZgy21QFVwx4EanNcKs7npEwiaj84eBvB0mwtQDdBbhCYlj0m1/Qng91Tyf7tgTp/COJ/4TGVxAfgOub6vl5NiKUCYVCkchlRNjPme9IyQ8f/u/gg6hCmAUFH2TfrY7ueT4WXppGRTvMnCHW4SQYC9xUsMm8iYHy0sZ5TrBJd9wdTsPh0F2k1MWjl7mfQiWre1mHK8wop1N9lRAPD0bYQ6Izy8Ht1e2APORZ7OaierHZqECyMligfw7wEOHCJ22C/FCHi5Oduph0k+prolCE1hZSfApSwyHR5/hir/XKshzXsSxtCquLeDB+s3GDG7exAcoAfX5mY09rtUik1MTJFsXFYhePFZPJggRzqFfFaquiL4SPw44akxJUhDs7Cmfken3Fw99IDViBqnGhIj5c9IM3peS6FroLozpOAtYRagMK5eWHv8lQyBl6WVYhPrzf1TTPN7nDx7clzVLc9oAzvRZGPJQVN9INaMQAfwn4ju/E2NcIfI96BY0hHxzI4DRJvejsNOkuRKNduQz+0tROkuCczLbGk07Lsgbtts05ud6Gpb1h0CNDvG8wo3J4CNvV00ZYr82tB28AsZNytX6se/neNPSqnBRNUV3XWgTVsXmzRUpjxLuca7VtcMwAY5XKTQzaTqxxwK1M/9AJbgFrK7SHpWWi99dgx+0apo6NLd6lXvfinxbGxYXim3RaLcdpg/lFrbRN/mUvAOZbjRgsLb0/IvZGArz/MtSxRPuJfeH7c9y3SfBu7rrFpY++euWdiDjN1qw0GyDeHpZWyem/7QUuGAP8RaOxdDwEw1qL4L6qjaloP6GYzEA+PIdwWdewX5/0/M2KKoI4IKAzsEmrc91zAd8ksLT43PJHyZJw71oN8WjA65SttUxW0IeiL0fP0KMpEXWODB2Lq+JsXJzrqNWwfgXzXa00vW657Z1mswN+71UKLzcDEjZUjYblnXExJZO9EzFhyAwPD3/kvBAnalAsQdht+xbx0H0Cvg6BGK65bqt2XRu3XUi5q69FpfD96elPAQsLkUrDYvgC6LlsKHIXagkAHgvCUpYhBwK+f+CbzE1bNJLFpqmVAN/E6OTi4dfQtcet9dd+nfPn+G9jQpKbBrMucBaZ8yxEtDCxvbM0PGaBqnwjlbu8zI1SBl04l1ctDFsa3AXPVqnduu5MZwrQMWL6nVUwJqOnb0rWBRq/ljsPRULTnjk/d6XYku6mVVEDppacC9JmEVuqWt0ouqIRHYL1ZG9dpKt5d/L6pxvEB6TGDSp/eBkJRWrE8navf3pp0F11A8fBPR4DMx6PsekrxHOsdKYl6GtXgl4y9M3/BYtAFthEvMHWAB8uudSnLw5fo9F0KnVgeOdyczyeI1C9Vjdd5jjweYiVkMlFpTO3/n/jz4DPAuBAKPRaKFyr+fjFgwY84TLqcnKevP3TIjxYglE6obY1cCCsNYfT9eDZx4cPs+M/wvaCqH8Dm5e6vd5wOHS8I3zvQErI7J3iG4v50MU2oeFX1HF2HD6Atrnz+EwB5Q8+e2dZjcCF//zF+8fynsx4p3Jil9qm+dBv6AI/SHDbHds9sv/oRMQbQaXh4xfGWQvUIiAVzfvlWDzWOinp1GknLNftdVvbj0+jvB7olz1FCnghAYIfE/jlZ2HzW1D+mG9oBFLO5BZicafz6VmaP0T8BOpmZisc7nBPe8N7LsCWpmDadpE9xlvtieMkWtOlx7zk0S9mBH/C0xDlMBcKT0u3/tMZr8JbKCS2mWnjI4SFbsWSxnYSsLaz9dXgp6ewC/wPGHqgliLT0gK/0IX6j5e8N7brcnGWyfTudP2pkth7l3ixGlz+FYQv4kO1Ug1zrMPuH3feyz0/0AGNmr3JjDzZfh0MxuNn+wBffrrxGI/tOYizFQlf164R/+6pGH/4A/x4Kcbe3t7T5bG3uvrd/cPys49f+B0Rb6z8+PL3v3+5vf07GH+EV8Hgd96AF4sPwRscK/tosv9rHR/vH6vfj38CsTg5hoHn6KUAAAAASUVORK5CYII=",23,77,94,96],"home":["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",47,69,96,71],"hover":["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",2,2,92,96],"link":["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",19,77,95,96],"move":["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",36,69,96,90],"normal":["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",2,2,94,96],"not_allowed":["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",30,68,96,87],"open":["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",73,55,96,68],"pan":["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",71,35,96,66],"precision":["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",30,75,91,96],"reload":["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",63,50,96,65],"resize_d1":["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",26,71,96,94],"resize_d2":["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",24,66,96,89],"resize_h":["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",47,77,96,93],"resize_v":["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",32,66,96,87],"search":["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",77,54,96,69],"text":["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",14,68,89,96],"working":["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",22,68,96,91],"zoom_in":["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",73,22,96,66],"zoom_out":["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",77,20,96,62]},CIMG={};
function cssU(d){return 'url("'+d+'")'}
function curRules(M){ /* M: name -> 'url(...) hx hy' */
 var g=function(n){return M[n]||M.normal};
 return 'html,html *{cursor:'+g('normal')+',auto !important}'+
 'a,button,select,summary,label,input[type=checkbox],input[type=radio],input[type=file],.seg label,.tabs button{cursor:'+g('hover')+',pointer !important}'+
 'a[href]{cursor:'+g('link')+',pointer !important}'+
 'button:active,.seg label:active{cursor:'+g('click')+',pointer !important}'+
 'textarea,input[type=text],input[type=number],input:not([type]){cursor:'+g('text')+',text !important}'+
 'button:disabled,select:disabled,input:disabled{cursor:'+g('not_allowed')+',not-allowed !important}'+
 'progress{cursor:'+g('working')+',progress !important}'+
 '#qbtn{cursor:'+g('close')+',pointer !important}.k-open{cursor:'+g('open')+',pointer !important}.k-search{cursor:'+g('search')+',pointer !important}.k-reload{cursor:'+g('reload')+',pointer !important}#logo{cursor:'+g('home')+',pointer !important}'}
function packCss(size,done){var names=Object.keys(CUR),left=names.length,M={};
 names.forEach(function(n){var d=CUR[n],im=new Image();im.onload=function(){var s=size/96,c=document.createElement('canvas');c.width=Math.max(1,Math.round(d[3]*s));c.height=Math.max(1,Math.round(d[4]*s));c.getContext('2d').drawImage(im,0,0,c.width,c.height);
  M[n]=cssU(c.toDataURL('image/png'))+' '+Math.round(d[1]*s)+' '+Math.round(d[2]*s);if(--left===0)done(curRules(M))};im.onerror=function(){if(--left===0)done(curRules(M))};im.src='data:image/png;base64,'+d[0]})}
var curSeq=0;
function applyCursor(){var st=$('cursorStyle');if(!st){st=document.createElement('style');st.id='cursorStyle';document.head.appendChild(st)}
 var v=$('curmode').value,size=parseInt($('curpx2').value,10)||32,my=++curSeq;
 $('curpick').classList.toggle('hide',v!=='custom');$('cursz').classList.toggle('hide',v==='default');
 if(v==='pack'){packCss(size,function(css){if(my===curSeq)st.textContent=css})}
 else if(v==='custom'){var url='';try{url=localStorage.getItem('md_cursor')||''}catch(e){}
  if(!url){st.textContent='';return}var im=new Image();im.onload=function(){var s=size/Math.max(im.width,im.height),c=document.createElement('canvas');c.width=Math.max(1,Math.round(im.width*s));c.height=Math.max(1,Math.round(im.height*s));c.getContext('2d').drawImage(im,0,0,c.width,c.height);var M={normal:cssU(c.toDataURL('image/png'))+' 1 1'};if(my===curSeq)st.textContent=curRules(M).split('}').slice(0,1).join('}')+'}'};im.src=url}
 else st.textContent=''}
$('curfile').addEventListener('change',function(){var f=this.files[0];if(!f)return;var r=new FileReader();r.onload=function(){var im=new Image();im.onload=function(){var s=96/Math.max(im.width,im.height),c=document.createElement('canvas');c.width=Math.max(1,Math.round(im.width*s));c.height=Math.max(1,Math.round(im.height*s));c.getContext('2d').drawImage(im,0,0,c.width,c.height);try{localStorage.setItem('md_cursor',c.toDataURL('image/png'))}catch(e){}applyCursor()};im.src=r.result};r.readAsDataURL(f)});
applyCursor();
</script></body></html>
'@
function Bg($sb,$a){ $rsp=[runspacefactory]::CreateRunspace(); $rsp.Open(); $p=[powershell]::Create(); $p.Runspace=$rsp
 [void]$p.AddScript($sb.ToString()); foreach($x in $a){ [void]$p.AddArgument($x) }; [void]$p.BeginInvoke() }
function ReadSettings{ if(Test-Path $settingsFile){ try{ return (Get-Content $settingsFile -Raw -Encoding UTF8|ConvertFrom-Json) }catch{} }; return $null }
function GetDl{ $s=ReadSettings; $d=$null; if($s -and $s.dlDir){ $d="$($s.dlDir)".Trim() }
 if(-not $d){ $d=$(if($env:YTDL_INSTALLED){ [IO.Path]::Combine($env:USERPROFILE,'Downloads','Media Downloader') }else{ [IO.Path]::Combine($dir,'Downloads') }) }
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
Write-Host "== Media Downloader $APPVER - by Andreas-Pinheiro =="
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
if($S.payload -and -not $TEST -and $WIN){ Bg $exeSb @($S,$lib,$cs,$csBasic,$setupCs); Write-Host '(building/updating Media-Downloader.exe in the background)' }
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
    '/api/openurl'{ try{ $u="$(($body|ConvertFrom-Json).url)"; if($u -match '^https://[^\s"]+$' -and $WIN -and -not $TEST){ Start-Process $u } }catch{} }
    '/api/shortcut'{ $out=@{msg=(Make-Shortcuts $false)}|ConvertTo-Json -Compress }
    '/api/quit'{ $S.stop=$true; $PL.stop=$true; KillTree $S.pid; KillTree $S.lpid; KillTree $S.ipid; $lst.Stop() }
   }
  }
  if($lst.IsListening -and $out){ $b=[Text.Encoding]::UTF8.GetBytes($out); $rs.ContentType=$ct; $rs.OutputStream.Write($b,0,$b.Length) }
 }catch{ try{ $rs.StatusCode=500 }catch{} }
 finally{ try{ $rs.Close() }catch{} }
}
try{ Remove-Item ([IO.Path]::Combine($bin,'port.txt')) -ea 0 }catch{}
