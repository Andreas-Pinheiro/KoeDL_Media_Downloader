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
  $S.running=$true; $S.stop=$false; $S.fails.Clear(); $S.alts.Clear(); $S.log.Clear(); $S.files.Clear(); $S.done=0; $S.pct=0; $S.item=''; $S.fixedItem=$false
  $stamp=$(if("$($o.stamp)" -match '^[0-9 :-]{8,20}$'){ "$($o.stamp)" }else{ (Get-Date).ToString('yyyy-MM-dd HH-mm') })
  $FL=New-Object Collections.ArrayList
  function FolderFor($plTitle){ switch("$($o.plmode)"){ 'none'{ return '' } 'new'{ return (Sanit $plTitle)+" [$stamp]/" } default{ return (Sanit $plTitle)+'/' } } }
  $useArc=("$($o.plmode)" -ne 'new')
  $fr=IntOf $o.frag; if($fr -lt 1 -or $fr -gt 16){ $fr=4 }
  $base=@('--ignore-errors','--no-colors','--newline','--windows-filenames','--trim-filenames','120','--retries','10','--fragment-retries','10','--extractor-retries','5','--concurrent-fragments',"$fr",'--no-mtime','--socket-timeout','30',
   '--progress-template','download:YTLP|%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s','--exec','echo YTLOK:{}','-P',$dl)
  if($o.safe){ $base+=@('--sleep-interval','2','--max-sleep-interval','6') }
  if("$($o.rate)" -match '^\d+[KkMm]$'){ $base+=@('--limit-rate',"$($o.rate)") }
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
    $dk=$(if($j.kind -eq 'v'){ "$($o.dirVideo)" }else{ "$($o.dirAudio)" }).Trim(); if($dk){ $args2+=@('-P',$dk) }
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

