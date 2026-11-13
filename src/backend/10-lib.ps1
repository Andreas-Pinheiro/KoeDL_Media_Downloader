# ------------------------------------------------------------------ funcoes comuns (reusadas nos runspaces)
$lib=@'
function J{ [IO.Path]::Combine([string[]]$args) }
function Tr($pt,$en){ if($S.lang -eq 'pt'){ return $pt }else{ return $en } }
function L($m){ try{ [void]$S.log.Add([string]$m); if($S.log.Count -gt 600){ $S.log.RemoveRange(0,100) } }catch{} }
function ErrTxt($ctx,$e){
 # Loga o detalhe tecnico e devolve uma frase amigavel para a interface.
 $d=''; try{ if($e){ $d="$($e.Exception.Message)"; if($e.ScriptStackTrace){ $d="$d | $($e.ScriptStackTrace -replace "`r?`n",' <- ')" } } }catch{}
 if($d){ L "[erro] ${ctx}: $d" }
 if($S){ $S.lastErr="${ctx}: $d" }
 return (Tr "Nao consegui $ctx. Tente de novo em instantes; se continuar, veja o log em Detalhes." "Could not $ctx. Please try again in a moment; if it keeps happening, check the log under Details.") }
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
 $exe=J $S.dir 'KoeDL.exe'; $target=$S.self; if(Test-Path $exe){ $target=$exe }
 $icon=''; try{ $f=J $S.bin 'app.ico'; [IO.File]::WriteAllBytes($f,[Convert]::FromBase64String($S.icoB64)); $icon="$f,0" }catch{ L "[atalho] icone: $($_.Exception.Message)" }
 $ws=New-Object -ComObject WScript.Shell; $made=@()
 foreach($loc in @([Environment]::GetFolderPath('Desktop'),[Environment]::GetFolderPath('Programs'))){
  $p=J $loc 'KoeDL.lnk'; $oldp=J $loc 'Media Downloader.lnk'; $migr=(Test-Path $oldp); if($migr){ try{ Remove-Item $oldp -Force -ea 0 }catch{} }
  if($only -and -not(Test-Path $p) -and -not $migr){ continue }
  try{ $l=$ws.CreateShortcut($p); $l.TargetPath=$target; $l.WorkingDirectory=$S.dir; if($icon){ $l.IconLocation=$icon }; $l.Save(); $made+=$loc }catch{ L "[atalho] $loc : $($_.Exception.Message)" } }
 if($made.Count){ return ((Tr 'Atalhos criados/atualizados em:' 'Shortcuts created/updated in:')+"`n"+($made -join "`n")) }
 return (Tr 'Nao consegui criar os atalhos.' 'Could not create the shortcuts.') }
function GetUpdBytes([string]$u){
 $ProgressPreference='SilentlyContinue'
 $r=Invoke-WebRequest $u -UseBasicParsing -TimeoutSec 40 -Headers @{'User-Agent'='KoeDL'}
 return ,$r.RawContentStream.ToArray() }
function GetUpdText([string]$u){ return [Text.Encoding]::UTF8.GetString([byte[]](GetUpdBytes $u)) }
function HashOk([byte[]]$bytes,[string]$sumsUrl){
 # Confere o SHA-256 do arquivo baixado com a linha "KoeDL.bat" do SHA256SUMS.txt da mesma release.
 try{ $st=GetUpdText $sumsUrl; $m=[regex]::Match($st,'(?im)^([0-9a-f]{64})\s+\*?KoeDL\.bat\s*$'); if(-not $m.Success){ return $false }
  $h=([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)) -replace '-','').ToLowerInvariant()
  return ($h -eq $m.Groups[1].Value.ToLowerInvariant()) }catch{ return $false } }
function AddUpdFrom($txt){
 # Valida o arquivo baixado: precisa ter o marcador e uma versao maior que a atual.
 $m=[regex]::Match($txt,'APPVER=.([0-9.]+).'); $ix=$txt.LastIndexOf('###'+'PS###')
 if(-not($m.Success -and $ix -ge 0 -and ([version]$m.Groups[1].Value) -gt ([version]$S.appver))){ return $false }
 $pl=$txt.Substring($ix+8); $t=$null; $e=$null; [void][Management.Automation.Language.Parser]::ParseInput($pl,[ref]$t,[ref]$e)
 if($e.Count -ne 0){ $S.chk='err'; L (Tr '(atualizacao do programa ignorada: arquivo invalido)' '(program update ignored: invalid file)'); return $false }
 $v=$m.Groups[1].Value; $S.updText=$pl; $S.chk='new'
 if($S.updAvail -ne $v){ $S.updAvail=$v; L (Tr "Ha uma versao nova do programa: $v (voce usa a $($S.appver))." "A new program version is available: $v (you have $($S.appver)).") }
 return $true }
function SelfUpdate($force){
 if(-not $S.selfUpd -and -not $force){ return }
 try{
  # URL fixa (testes e forks): compara direto pelo APPVER do arquivo. Sem hash so se YTDL_NOHASH estiver definido.
  if($env:YTDL_UPDURL){
   $by=[byte[]](GetUpdBytes $env:YTDL_UPDURL)
   if(-not $env:YTDL_NOHASH){ $sm=$(if($env:YTDL_UPDSUMS){ $env:YTDL_UPDSUMS }else{ ($env:YTDL_UPDURL -replace '[^/]+$','SHA256SUMS.txt') })
    if(-not (HashOk $by $sm)){ $S.chk='err'; L (Tr '(atualizacao ignorada: o SHA-256 do arquivo nao confere)' '(update ignored: the file SHA-256 does not match)'); return } }
   $txt=[Text.Encoding]::UTF8.GetString($by)
   if(-not (AddUpdFrom $txt)){ if($force){ $S.updAvail=''; $S.chk='same'; L (Tr 'O programa ja esta na versao mais recente.' 'The program is already up to date.') } }
   return }
  $repos='Andreas-Pinheiro/KoeDL_Media_Downloader','Andreas-Pinheiro/Media-Downloader'
  # 1) Releases do GitHub: a versao vem da API e o arquivo vem do asset da release (sem ler a branch)
  $rel=$null; $why=''
  foreach($repo in $repos){
   $api=$(if($env:YTDL_UPDAPI){ $env:YTDL_UPDAPI }else{ "https://api.github.com/repos/$repo/releases/latest" })
   try{ $rel=Invoke-RestMethod $api -TimeoutSec 30 -Headers @{'User-Agent'='KoeDL';'Accept'='application/vnd.github+json'}
    if($rel -and $rel.tag_name){ break } }
   catch{ $rel=$null; $why=$_.Exception.Message }
   if($env:YTDL_UPDAPI){ break } }
  $cands=@(); $nv=''
  if($rel){
   $tag="$($rel.tag_name)".Trim(); $nv=($tag -replace '^[vV]','')
   if(-not($nv -match '^\d+(\.\d+){1,3}$')){ $S.chk='err'; L (Tr "A release mais recente ($tag) tem um numero de versao que eu nao entendi." "The latest release ($tag) has a version number I could not read."); return }
   if(([version]$nv) -le ([version]$S.appver)){
    $S.updAvail=''
    if($force){ $S.chk='same'; L (Tr 'O programa ja esta na versao mais recente.' 'The program is already up to date.') }
    return }
   $ub=''; $us=''
   foreach($a in @($rel.assets)){ if($a.browser_download_url){ if("$($a.name)" -eq 'KoeDL.bat'){ $ub="$($a.browser_download_url)" } elseif("$($a.name)" -eq 'SHA256SUMS.txt'){ $us="$($a.browser_download_url)" } } }
   if($ub){ $cands+=,@($ub,$(if($us){ $us }else{ $ub -replace '[^/]+$','SHA256SUMS.txt' })) }
   foreach($repo in $repos){ $cands+=,@("https://github.com/$repo/releases/download/$tag/KoeDL.bat","https://github.com/$repo/releases/download/$tag/SHA256SUMS.txt") } }
  else{
   # 2) Plano B: a API falhou (limite de consultas, rede da empresa...). O link "latest/download" nao usa a API.
   if($why){ L "[upd] $why" }
   foreach($repo in $repos){ $cands+=,@("https://github.com/$repo/releases/latest/download/KoeDL.bat","https://github.com/$repo/releases/latest/download/SHA256SUMS.txt") } }
  $why=''; $reached=$false
  foreach($c in $cands){
   try{ $by=[byte[]](GetUpdBytes $c[0]); $txt=[Text.Encoding]::UTF8.GetString($by)
    if($txt -notmatch '###'+'PS###'){ $why='conteudo inesperado'; continue }
    $reached=$true
    $m=[regex]::Match($txt,'APPVER=.([0-9.]+).')
    if($m.Success -and ([version]$m.Groups[1].Value) -le ([version]$S.appver)){ $S.updAvail=''; if($force){ $S.chk='same'; L (Tr 'O programa ja esta na versao mais recente.' 'The program is already up to date.') }; return }
    if(-not (HashOk $by $c[1])){ $S.chk='err'; L (Tr '(atualizacao ignorada: o SHA-256 do arquivo nao confere com o da release)' '(update ignored: the file SHA-256 does not match the release)'); return }
    if(AddUpdFrom $txt){ return }
    $why='arquivo invalido'; break }
   catch{ $why=$_.Exception.Message } }
  $S.chk='err'
  if($nv){ L (Tr "A versao $nv existe, mas nao consegui baixar o arquivo dela agora. Tente de novo mais tarde." "Version $nv exists, but its file could not be downloaded right now. Try again later.") }
  else{ L (Tr 'Nao consegui consultar as versoes no GitHub. Verifique sua conexao e tente de novo.' 'Could not check the versions on GitHub. Check your connection and try again.') }
  if($why){ L "[upd] $why" }
 }catch{ $S.chk='err'; L (Tr 'Nao consegui verificar atualizacoes do programa agora. Tente de novo mais tarde.' 'Could not check for program updates right now. Try again later.'); L "[upd] $($_.Exception.Message)" } }
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
  if($ln -match '^YTLOK:\s*"?(.+?)"?\s*$'){ [void]$S.files.Add([string]$matches[1]); $S.cur=Split-Path $matches[1] -Leaf; $n++; L ('[ok] '+$S.cur); continue }
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
# ---------------------------------------------------------------- integridade das dependencias
# Politica: hash publicado pela propria origem e obrigatorio. Divergencia = arquivo descartado.
# Se a origem nao publica (ou nao conseguimos ler) o hash, o arquivo entra com aviso e fica
# registrado como verificado=false em bin/deps.json, junto com o sha256 local.
function Sha256File($p){ try{ return ((Get-FileHash -LiteralPath $p -Algorithm SHA256 -ea 1).Hash).ToLowerInvariant() }catch{ return '' } }
function SigOf($p){ try{ $s=Get-AuthenticodeSignature -LiteralPath $p -ea 1
  if($s.Status -eq 'Valid'){ $n="$($s.SignerCertificate.Subject)"; if($n -match 'CN=([^,]+)'){ $n=$matches[1] }; return "Valid: $n" }
  return "$($s.Status)" }catch{ return 'Unknown' } }
function DepHostsOk($u){ try{ $x=[uri]$u }catch{ return $false }
 if($env:YTDL_DEP_INSECURE -eq '1'){ return $true }
 if($x.Scheme -ne 'https'){ return $false }
 $h=$x.Host.ToLowerInvariant()
 return (@('github.com','api.github.com','objects.githubusercontent.com','release-assets.githubusercontent.com','codeload.github.com','api.nuget.org','globalcdn.nuget.org') -contains $h) }
function DepText($u){ $ProgressPreference='SilentlyContinue'
 if(-not (DepHostsOk $u)){ L "[hash] origem recusada: $u"; return '' }
 try{ $r=Invoke-WebRequest $u -UseBasicParsing -TimeoutSec 40 -Headers @{'User-Agent'='KoeDL'}
  if($r.Content -is [byte[]]){ return [Text.Encoding]::UTF8.GetString($r.Content) }
  return "$($r.Content)" }catch{ L "[hash] nao consegui ler $u : $($_.Exception.Message)"; return '' } }
function DepSumFor($txt,$name){
 # Aceita o formato GNU ("hash  arquivo") e o bloco "Hash : HASH" que o deno publica.
 foreach($ln in (("$txt") -split "`r?`n")){ $s=$ln.Trim(); if(-not $s){ continue }
  if($s -match '^([0-9a-fA-F]{64})\s+\*?(.+)$'){ if($matches[2].Trim() -eq $name){ return $matches[1].ToLowerInvariant() } } }
 $m=[regex]::Match("$txt",'(?im)^\s*Hash\s*:\s*([0-9a-f]{64})\s*$')
 if($m.Success){ return $m.Groups[1].Value.ToLowerInvariant() }
 return '' }
function DepsAdd($n,$v,$sha,$src,$ok,$sig){ $f=J $S.bin 'deps.json'; $a=@()
 try{ if(Test-Path $f){ $a=@([IO.File]::ReadAllText($f,[Text.Encoding]::UTF8)|ConvertFrom-Json) } }catch{}
 $a=@($a|Where-Object{ "$($_.n)" -ne "$n" })
 $a+=,[pscustomobject]@{n="$n";v="$v";sha256="$sha";src="$src";verified=[bool]$ok;sig="$sig";at=(Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')}
 try{ [IO.File]::WriteAllText($f,(ConvertTo-Json -InputObject @($a) -Depth 4),(New-Object Text.UTF8Encoding $false)) }catch{}
 L ("[deps] $n $v hash=$sha origem="+$(if($ok){'conferida'}else{'NAO conferida'})+" sig=$(if($sig){$sig}else{'-'})") }
function DepsVer($map){ $f=J $S.bin 'deps.json'; if(-not(Test-Path $f)){ return }
 $a=@(); try{ $a=@([IO.File]::ReadAllText($f,[Text.Encoding]::UTF8)|ConvertFrom-Json) }catch{ return }
 $ch=$false
 foreach($r in $a){ foreach($k in $map.Keys){ if("$($r.n)" -like "*$k*"){ if($map[$k] -and "$($r.v)" -ne "$($map[$k])"){ $r|Add-Member -NotePropertyName v -NotePropertyValue "$($map[$k])" -Force; $ch=$true } } } }
 if($ch){ try{ [IO.File]::WriteAllText($f,(ConvertTo-Json -InputObject @($a) -Depth 4),(New-Object Text.UTF8Encoding $false)) }catch{} } }
function DepGet($urls,$out,$sumUrls,$name,$ver){
 # Baixa para um temporario, confere o SHA-256 publicado pela mesma release e so entao grava em $out.
 $i=0; $err=''
 foreach($url in @($urls)){ $i++; $tmp="$out.dep"
  if(-not (DepHostsOk $url)){ $err='origem nao permitida'; L "[hash] origem recusada: $url"; continue }
  Remove-Item $tmp -ea 0
  if(-not (GetFile @($url) $tmp)){ $err=$S.lastErr; continue }
  $h=Sha256File $tmp; $want=''; $su=''
  if($sumUrls){ $cs=@($sumUrls); if($cs.Count -ge $i){ $su="$($cs[$i-1])" } }
  if($su){ $want=(DepSumFor (DepText $su) $name) }
  if($want -and $h -ne $want){
   L (Tr "!!! ${name}: o SHA-256 nao confere (a release diz $want, o arquivo tem $h). Arquivo descartado." "!!! ${name}: SHA-256 mismatch (release says $want, file has $h). File discarded.")
   Remove-Item $tmp -ea 0; $err='hash nao confere'; continue }
  if($want){ L "[hash] $name ok ($h)" }
  else{ L (Tr "[hash] ${name}: sem hash publicado legivel ($su) - sha256 local $h" "[hash] ${name}: no readable published hash ($su) - local sha256 $h") }
  Move-Item $tmp $out -Force
  DepsAdd $name $ver $h $url ([bool]$want) ''
  return $true }
 $S.lastErr=$err; return $false }
function DepZip($urls,$sumUrls,$name,$pat,$ver){
 $z=J ([IO.Path]::GetTempPath()) ('dep_'+[guid]::NewGuid().ToString('N')+'.zip'); $x="$z.d"
 if(-not (DepGet $urls $z $sumUrls $name $ver)){ return $false }
 try{ Expand-Archive $z $x -Force; $n=0
  foreach($f in (Get-ChildItem $x -Recurse -Include $pat -File -ea 0)){
   $dst=J $S.bin $f.Name; Copy-Item $f.FullName $dst -Force; $n++
   $sg=SigOf $dst; $h=Sha256File $dst
   L "[sig] $($f.Name): $sg"
   if($sg -notmatch '^Valid'){ L (Tr "[sig] AVISO: $($f.Name) nao tem assinatura digital valida" "[sig] WARNING: $($f.Name) has no valid digital signature") }
   DepsAdd $f.Name $ver $h $name $true $sg }
  return ($n -gt 0) }catch{ L (Tr "falha ao extrair: $($_.Exception.Message)" "failed to extract: $($_.Exception.Message)"); return $false }
 finally{ Remove-Item $z,$x -Recurse -Force -ea 0 } }
'@

. ([scriptblock]::Create($lib))

