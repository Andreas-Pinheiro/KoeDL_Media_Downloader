# ------------------------------------------------------------------ conversao de video em audio (aba "Converter")
# Os arquivos entram na lista sempre pelo seletor do proprio programa (OpenFileDialog), nunca por caminho
# enviado pela pagina: assim a interface nao consegue pedir a conversao de um arquivo qualquer do disco.
$CVFmt=@{'mp3'='mp3';'m4a'='m4a';'opus'='opus';'flac'='flac';'wav'='wav'}
$CVQ=@('128','192','256','320')
$CVExt=@('.mp4','.mkv','.webm','.mov','.m4v','.avi','.flv','.wmv','.ts','.mpg','.mpeg','.mp3','.m4a','.opus','.ogg','.flac','.wav','.aac','.wma','.3gp')
function FFexe($n){
 $c=Get-Command $n -ea 0; if($c){ return $c.Source }
 $e=$(if($S.win){'.exe'}else{''}); $f=J $S.bin "$n$e"
 if(Test-Path -LiteralPath $f){ return $f }
 return $n }
# duracao em segundos (0 quando o ffprobe nao consegue ler)
function MediaDur($fp){
 try{
  $psi=New-Object Diagnostics.ProcessStartInfo (FFexe 'ffprobe')
  $psi.Arguments='-v error -show_entries format=duration -of default=nw=1:nk=1 '+('"'+($fp -replace '"','\"')+'"')
  $psi.UseShellExecute=$false; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true; $psi.CreateNoWindow=$true
  $psi.StandardOutputEncoding=[Text.Encoding]::UTF8; $psi.StandardErrorEncoding=[Text.Encoding]::UTF8
  $p=[Diagnostics.Process]::Start($psi); $o=$p.StandardOutput.ReadToEnd(); [void]$p.WaitForExit(20000)
  $d=0.0; $ok=[double]::TryParse("$o".Trim(),[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$d)
  if($ok){ return $d }
 }catch{}
 return 0.0 }
# O worker roda num runspace separado, que so enxerga o que esta no $lib: por isso ele carrega as proprias
# funcoes de ffmpeg aqui dentro (nada de depender de funcao deste arquivo).
$cvSb={ param($S,$CV,$lib,$opt)
 . ([scriptblock]::Create($lib))
 function _ff($n){ $c=Get-Command $n -ea 0; if($c){ return $c.Source }
  $e=$(if($S.win){'.exe'}else{''}); $f=J $S.bin "$n$e"; if(Test-Path -LiteralPath $f){ return $f }; return $n }
 function _dur($fp){ try{
   $psi=New-Object Diagnostics.ProcessStartInfo (_ff 'ffprobe')
   $psi.Arguments='-v error -show_entries format=duration -of default=nw=1:nk=1 '+('"'+($fp -replace '"','\"')+'"')
   $psi.UseShellExecute=$false; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true; $psi.CreateNoWindow=$true
   $psi.StandardOutputEncoding=[Text.Encoding]::UTF8; $psi.StandardErrorEncoding=[Text.Encoding]::UTF8
   $p=[Diagnostics.Process]::Start($psi); $o=$p.StandardOutput.ReadToEnd(); [void]$p.WaitForExit(20000)
   $d=0.0; $ok=[double]::TryParse("$o".Trim(),[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$d)
   if($ok){ return $d } }catch{}; return 0.0 }
 function _args($fmt,$q){ switch($fmt){
   'mp3' { return @('-vn','-map','0:a:0','-c:a','libmp3lame','-b:a',"${q}k",'-id3v2_version','3','-map_metadata','0') }
   'm4a' { return @('-vn','-map','0:a:0','-c:a','aac','-b:a',"${q}k",'-movflags','+faststart','-map_metadata','0') }
   'opus'{ return @('-vn','-map','0:a:0','-c:a','libopus','-b:a',"${q}k",'-map_metadata','0') }
   'flac'{ return @('-vn','-map','0:a:0','-c:a','flac','-compression_level','5','-map_metadata','0') }
   'wav' { return @('-vn','-map','0:a:0','-c:a','pcm_s16le') } }
  return @('-vn','-map','0:a:0','-c:a','libmp3lame','-b:a','192k') }
 function _free($dir,$base,$ext){ $f=J $dir ($base+'.'+$ext); $n=1
  while(Test-Path -LiteralPath $f){ $n++; $f=J $dir ($base+" ($n)."+$ext) }; return $f }
 function _q($a){ ($a|ForEach-Object{ if("$_" -match '[\s"]' -or "$_" -eq ''){ '"'+("$_" -replace '"','\"')+'"' }else{ "$_" } }) -join ' ' }
 try{
  $CV.err=''; $CV.stop=$false; $CV.busy=$true
  $todo=@($CV.items.ToArray()|Where-Object{ $_.status -eq 'wait' })
  $CV.n=$todo.Count
  foreach($it in $todo){
   if($CV.stop){ break }
   try{
    $CV.cur="$($it.name)"; $CV.pct=0; $it.status='run'; $it.pct=0; $it.msg=''
    $src="$($it.path)"
    if(-not(Test-Path -LiteralPath $src)){ $it.status='err'; $it.msg=(Tr 'arquivo nao encontrado' 'file not found'); continue }
    $dir=$(if("$($opt.dest)".Trim()){ "$($opt.dest)".Trim() }else{ [IO.Path]::GetDirectoryName($src) })
    try{ New-Item -ItemType Directory -Force $dir | Out-Null }catch{}
    $outF=_free $dir ([IO.Path]::GetFileNameWithoutExtension($src)) $opt.fmt
    $it.out=$outF
    $dd=0.0; try{ $dd=[double]$it.dur }catch{}
    if($dd -le 0){ $dd=(_dur $src); $it.dur=$dd }
    $argv=@('-hide_banner','-nostdin','-y','-loglevel','error','-progress','pipe:1','-i',$src)+@(_args $opt.fmt $opt.q)+@($outF)
    $psi=New-Object Diagnostics.ProcessStartInfo (_ff 'ffmpeg'); $psi.Arguments=(_q $argv)
    $psi.UseShellExecute=$false; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true; $psi.CreateNoWindow=$true
    $psi.StandardOutputEncoding=[Text.Encoding]::UTF8; $psi.StandardErrorEncoding=[Text.Encoding]::UTF8
    $p=[Diagnostics.Process]::Start($psi); $CV.pid=$p.Id
    while(($ln=$p.StandardOutput.ReadLine()) -ne $null){
     if($CV.stop){ try{ $p.Kill() }catch{}; break }
     if($ln -match '^out_time_us=(\d+)$'){ $us=[double]$Matches[1]
      if($dd -gt 0){ $pc=[int][Math]::Min(99,[Math]::Round($us/1000000.0/$dd*100)); if($pc -gt [int]$CV.pct){ $CV.pct=$pc; $it.pct=$pc } } } }
    $errTxt=''; try{ $errTxt="$($p.StandardError.ReadToEnd())".Trim() }catch{}
    try{ [void]$p.WaitForExit(30000) }catch{}
    $CV.pid=0; $CV.pct=0
    if(Test-Path -LiteralPath $outF){ $it.pct=100; $it.status='done'; $it.size=((New-Object IO.FileInfo($outF)).Length)
     if($opt.del){ try{ Remove-Item -LiteralPath $src -Force }catch{} }
     L ("[conv] $($it.name) -> $([IO.Path]::GetFileName($outF))") }
    else{ $it.status='err'
     $it.msg=$(if($errTxt){ ($errTxt -split "`n"|Where-Object{ "$_".Trim() }|Select-Object -Last 1).Trim() }else{ (Tr 'falha ao converter' 'conversion failed') }) }
   }catch{ $it.status='err'; $it.msg=$_.Exception.Message; $CV.err=$_.Exception.Message }
  }
  if($CV.stop){ foreach($x in @($CV.items.ToArray())){ if($x.status -eq 'run'){ $x.status='wait' } } }
 }catch{ $CV.err=$_.Exception.Message }
 finally{ $CV.busy=$false; $CV.cur=''; $CV.pct=0; $CV.stop=$false }
}
