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

