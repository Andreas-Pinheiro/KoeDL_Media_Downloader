# ------------------------------------------------------------------ inicio
Write-Host "== KoeDL $APPVER - by Andreas-Pinheiro =="
$S.chan=$(if($(ReadSettings).chan){ "$((ReadSettings).chan)" }else{ 'stable' })
$S.lang=$(if($(ReadSettings).lang -eq 'pt'){ 'pt' }else{ 'en' })
$S.selfUpd=-not ($(ReadSettings).selfUpd -eq $false)
$S.icoB64=$icoB64.Trim(); $S.logoB64=$logoB64.Trim()
if($self -and $self -match '\.(bat|ps1|cmd)$' -and (Test-Path $self) -and -not $env:YTDL_EXE){
 $raw=[IO.File]::ReadAllText($self,[Text.Encoding]::UTF8); $ix=$raw.LastIndexOf('###'+'PS###')
 $S.payload=$(if($ix -ge 0){ $raw.Substring($ix+8) }else{ $raw }) }
elseif($env:YTDL_EXE){
 # Rodando pelo .exe: o titulo, a bandeja e o icone ficam dentro do .exe, entao o .exe precisa ser refeito quando o programa atualiza.
 try{ $pf=$(if($env:YTDL_OVR -and (Test-Path $updFile)){ $updFile }else{ [IO.Path]::Combine($bin,'app.ps1') }); if(Test-Path $pf){ $S.payload=[IO.File]::ReadAllText($pf,[Text.Encoding]::UTF8) } }catch{ L "[app] nao consegui ler o codigo do .exe: $($_.Exception.Message)" } }
Bg $prepSb @($S,$lib,$false)
if(($WIN -and -not $TEST) -or $env:YTDL_WV2TEST){ Bg $wv2Sb @($S,$lib) }
if(-not $TEST){ Bg $schedSb @($S,$lib,$prepSb.ToString()) }
$lst=$null; $port=8765
while($port -lt 8790){ $l=New-Object Net.HttpListener; $l.Prefixes.Add("http://127.0.0.1:$port/"); try{ $l.Start(); $lst=$l; break }catch{ $port++ } }
if(-not $lst){ Write-Host (Tr 'Nao encontrei uma porta livre para a interface (8765-8789). Feche outras copias do KoeDL e abra de novo.' 'Could not find a free port for the interface (8765-8789). Close other KoeDL copies and open it again.'); return }
[IO.File]::WriteAllText([IO.Path]::Combine($bin,'port.txt'),"$port")
Write-Host "Ready! Opening http://127.0.0.1:$port/"
if($S.payload -and -not $TEST -and $WIN){ Bg $exeSb @($S,$lib,$cs,$csBasic,$setupCs); Write-Host '(building/updating KoeDL.exe in the background)' }
if(-not $env:YTDL_EXE -and (-not $TEST -or $env:YTDL_BROWSER)){ Open-Ui $port }

$flagSc=[IO.Path]::Combine($bin,'shortcuts2.done')
if($WIN -and -not $TEST -and -not(Test-Path $flagSc)){ try{ [void](Make-Shortcuts $false); Set-Content $flagSc (Get-Date -Format s); Write-Host 'Shortcuts created on the Desktop and Start Menu.' }catch{} }
$first=$true
while($lst.IsListening){
 $ctx=$lst.GetContext(); $rq=$ctx.Request; $rs=$ctx.Response
 try{
  try{ $rs.AddHeader('X-Content-Type-Options','nosniff'); $rs.AddHeader('Referrer-Policy','no-referrer'); $rs.AddHeader('X-Frame-Options','DENY') }catch{}
  $path=$rq.Url.AbsolutePath; $body=''
  if($rq.HasEntityBody){ $body=(New-Object IO.StreamReader($rq.InputStream,[Text.Encoding]::UTF8)).ReadToEnd() }
  $out='{}'; $ct='application/json; charset=utf-8'
  $hostOk=("$($rq.Headers['Host'])" -match '^(127\.0\.0\.1|localhost)(:\d+)?$')
  # Defesa em profundidade: alem do token, escrita so com o cabecalho da propria interface
  # (site externo nao manda cabecalho customizado sem preflight/CORS) e Origin so do proprio app.
  $org="$($rq.Headers['Origin'])"
  $orgOk=(-not $org -or $org -match '^https?://(127\.0\.0\.1|localhost)(:\d+)?$')
  $wr=($rq.HttpMethod -eq 'POST' -or $rq.HttpMethod -eq 'PUT' -or $rq.HttpMethod -eq 'PATCH' -or $rq.HttpMethod -eq 'DELETE')
  $csrfOk=(-not $wr -or "$($rq.Headers['X-KoeDL'])" -eq '1')
  if(-not $hostOk){ $rs.StatusCode=403; $out='' }
  elseif(-not $orgOk -or -not $csrfOk){ $rs.StatusCode=403; $out='' }
  elseif($path -eq '/'){ $out=$html.Replace('__TOK__',$tok); $ct='text/html; charset=utf-8' }
  elseif($rq.QueryString['t'] -ne $tok){ $rs.StatusCode=403 }
  else{
   switch($path){
    '/api/status'{ $out=@{appver=$S.appver;updavail="$($S.updAvail)";chk="$($S.chk)";running=$S.running;ready=$S.ready;prep=$S.prep;note=$S.note;ver=$S.ver;status=$S.status;pct=$S.pct;speed=$S.speed;eta=$S.eta;item=$S.item;cur=$S.cur;browser=$S.browser;done=$S.done;total=$S.total;
       files=@($S.files.ToArray()|Select-Object -First 60);nfiles=$S.files.Count;log=@($S.log.ToArray()|Select-Object -Last 90);fails=@($S.fails.ToArray());alts=@($S.alts.ToArray())}|ConvertTo-Json -Depth 4 -Compress }
    '/api/settings'{ if($rq.HttpMethod -eq 'POST'){ try{ $null=$body|ConvertFrom-Json; [IO.File]::WriteAllText($settingsFile,$body,(New-Object Text.UTF8Encoding $false)); $sj=$body|ConvertFrom-Json; if($sj.chan){ $S.chan="$($sj.chan)" }; $S.lang=$(if($sj.lang -eq 'pt'){ 'pt' }else{ 'en' }); if($sj.PSObject.Properties['selfUpd']){ $S.selfUpd=[bool]$sj.selfUpd } }catch{ L "[config] nao consegui salvar o settings.json: $($_.Exception.Message)" } }
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
    '/api/chkupd'{ if($S.chk -ne 'run'){ $S.chk='run'; Bg { param($S,$lib) . ([scriptblock]::Create($lib)); try{ SelfUpdate $true }catch{ L "[upd] $($_.Exception.Message)" }; if($S.chk -eq 'run'){ $S.chk='err' } } @($S,$lib) } }
    '/api/update'{ if($S.running){ $out=@{error=(Tr 'Espere o download terminar para atualizar.' 'Wait for the download to finish before updating.')}|ConvertTo-Json -Compress }else{ Bg $prepSb @($S,$lib,$true) } }
    '/api/winsize'{ try{ $o=$body|ConvertFrom-Json; if($o.w -ge 600 -and $o.h -ge 500){ Set-Content ([IO.Path]::Combine($bin,'win.txt')) "$([int]$o.x),$([int]$o.y),$([int]$o.w),$([int]$o.h),0" } }catch{ L "[janela] nao consegui guardar o tamanho: $($_.Exception.Message)" } }
    '/api/clip'{ $ct=''; try{ if($WIN -and -not $TEST){ $ps=New-Object Diagnostics.ProcessStartInfo 'powershell.exe'; $ps.Arguments='-NoProfile -STA -Command "[Console]::OutputEncoding=[Text.Encoding]::UTF8; Add-Type -AssemblyName System.Windows.Forms; [Windows.Forms.Clipboard]::GetText()"'; $ps.UseShellExecute=$false; $ps.CreateNoWindow=$true; $ps.RedirectStandardOutput=$true; $pr=[Diagnostics.Process]::Start($ps); $cx=$pr.StandardOutput.ReadToEnd(); [void]$pr.WaitForExit(4000); $cx=$cx.Trim(); if($cx -match '^https?://\S+$' -and $cx.Length -lt 2000){ $ct=$cx } }
   elseif(-not $WIN){ foreach($c in @('wl-paste','xclip','xsel')){ if(Get-Command $c -ea 0){ try{ $t=$(if($c -eq 'wl-paste'){ (& wl-paste -n 2>$null|Out-String) }elseif($c -eq 'xclip'){ (& xclip -selection clipboard -o 2>$null|Out-String) }else{ (& xsel -b 2>$null|Out-String) }).Trim(); if($t -match '^https?://\S+$' -and $t.Length -lt 2000){ $ct=$t; break } }catch{} } } }
  }catch{}; $out=@{text=$ct}|ConvertTo-Json -Compress }
    '/api/openurl'{ try{ $u="$(($body|ConvertFrom-Json).url)"; if($u -match '^https://[^\s"]+$' -and $WIN -and -not $TEST){ Start-Process $u } }catch{} }
    '/api/history'{ $hf=J $bin 'history.json'
      if($rq.HttpMethod -eq 'POST'){ try{ $hb=$body|ConvertFrom-Json; $cur=@(); if(Test-Path $hf){ try{ $cur=@(Get-Content $hf -Raw -Encoding UTF8|ConvertFrom-Json) }catch{} }
         if($hb.clear){ $cur=@() }else{ $cur=@($hb.entry)+$cur }
         $cur=@($cur|Select-Object -First 300); [IO.File]::WriteAllText($hf,(ConvertTo-Json -InputObject @($cur) -Depth 5),(New-Object Text.UTF8Encoding $false)); $out='{"ok":true}' }catch{ $out=@{error=(ErrTxt (Tr 'salvar o historico' 'save the history') $_)}|ConvertTo-Json -Compress } }
      else{ if(Test-Path $hf){ $out=[IO.File]::ReadAllText($hf,[Text.Encoding]::UTF8) }else{ $out='[]' } } }
    '/api/queue'{ $qf=J $bin 'queue.json'
      if($rq.HttpMethod -eq 'POST'){ try{ if($body.Length -gt 2000000){ throw 'fila grande demais' }; $null=$body|ConvertFrom-Json; [IO.File]::WriteAllText($qf,$body,(New-Object Text.UTF8Encoding $false)); $out='{"ok":true}' }catch{ $out=@{error=(ErrTxt (Tr 'salvar a fila' 'save the queue') $_)}|ConvertTo-Json -Compress } }
      else{ if(Test-Path $qf){ $out=[IO.File]::ReadAllText($qf,[Text.Encoding]::UTF8) }else{ $out='[]' } } }
    '/api/library'{ $ea='.mp3','.m4a','.opus','.ogg','.flac','.wav','.aac','.wma'; $ev='.mp4','.mkv','.webm','.mov','.m4v','.avi'; $seen=@{}; $li=New-Object Collections.ArrayList
      foreach($r in (DlRoots)){ if(-not(Test-Path -LiteralPath $r)){ continue }; $rrf=[IO.Path]::GetFullPath($r).TrimEnd('\','/')
        foreach($f in (Get-ChildItem -LiteralPath $r -Recurse -Depth 6 -File -ea 0)){ $x=$f.Extension.ToLower(); $isA=($ea -contains $x); if(-not $isA -and -not ($ev -contains $x)){ continue }
          if($seen.ContainsKey($f.FullName)){ continue }; $seen[$f.FullName]=1; $dn=$f.Directory.Name; if([IO.Path]::GetFullPath($f.DirectoryName).TrimEnd('\','/') -eq $rrf){ $dn='' }
          [void]$li.Add([ordered]@{p=$f.FullName;n=$f.BaseName;k=$(if($isA){'a'}else{'v'});s=$f.Length;t=$f.LastWriteTime.ToString('s');d=$dn}) } }
      $srt=@($li|Sort-Object @{Expression={$_.t};Descending=$true}|Select-Object -First 5000); $out=ConvertTo-Json -InputObject $srt -Depth 3 -Compress }
    '/api/deps'{ $df=J $bin 'deps.json'; if(Test-Path $df){ $out=[IO.File]::ReadAllText($df,[Text.Encoding]::UTF8) }else{ $out='[]' } }
    '/api/libdirs'{ $lf=LibFile
      if($rq.HttpMethod -eq 'POST'){ try{ $ok=@(); $bad=@()
          foreach($d in @(($body|ConvertFrom-Json).dirs)){ $d="$d".Trim(); if(-not $d){ continue }
            try{ if(-not [IO.Path]::IsPathRooted($d) -or -not (Test-Path -LiteralPath $d -PathType Container)){ $bad+=$d; continue }
              $fu=[IO.Path]::GetFullPath($d); if($fu.TrimEnd('\','/').Length -le 2){ $bad+=$d; continue }; $fu=$fu.TrimEnd('\','/')
              if(-not ($ok | Where-Object { $_ -ieq $fu })){ $ok+=$fu } }catch{ $bad+=$d } }
          [IO.File]::WriteAllText($lf,(ConvertTo-Json -InputObject @($ok) -Compress),(New-Object Text.UTF8Encoding $false))
          $out=@{ok=$true;dirs=$ok;bad=$bad}|ConvertTo-Json -Compress -Depth 3
        }catch{ $out=@{error=(ErrTxt (Tr 'salvar as pastas' 'save the folders') $_)}|ConvertTo-Json -Compress } }
      else{ $ds=@(); foreach($d in (LibDirs)){ $ds+=[ordered]@{p=$d;ok=[bool](Test-Path -LiteralPath $d -PathType Container)} }
        $bs=@(); foreach($d in (DlBase)){ $bs+=$d }
        $out=@{dirs=$ds;base=$bs}|ConvertTo-Json -Compress -Depth 4 } }
    '/api/pickfolder'{ if($rq.HttpMethod -eq 'POST'){
        if($S.pick -and $S.pick.busy){ $out='{"busy":true}' }
        elseif($WIN -and -not $TEST){ $S.pick=@{busy=$true;path=''}
          Bg { param($S)
            try{ $cmd='[Console]::OutputEncoding=[Text.Encoding]::UTF8; Add-Type -AssemblyName System.Windows.Forms; $o=New-Object Windows.Forms.Form; $o.TopMost=$true; $o.ShowInTaskbar=$false; $o.Opacity=0; $o.StartPosition="CenterScreen"; $o.Show(); $f=New-Object Windows.Forms.FolderBrowserDialog; $f.Description="KoeDL"; if($f.ShowDialog($o) -eq "OK"){ $f.SelectedPath }; $o.Close()'
              $psi=New-Object Diagnostics.ProcessStartInfo 'powershell.exe'; $psi.Arguments='-NoProfile -STA -WindowStyle Hidden -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
              $psi.UseShellExecute=$false; $psi.RedirectStandardOutput=$true; $psi.CreateNoWindow=$true; $psi.StandardOutputEncoding=[Text.Encoding]::UTF8
              $pr=[Diagnostics.Process]::Start($psi); $o2=$pr.StandardOutput.ReadToEnd(); [void]$pr.WaitForExit(600000); $S.pick=@{busy=$false;path=("$o2".Trim())}
            }catch{ $S.pick=@{busy=$false;path=''} } } @($S)
          $out='{"busy":true}' }
        else{ $out='{"busy":false,"path":""}' } }
      else{ $pk=$S.pick; if($pk){ $out=@{busy=[bool]$pk.busy;path="$($pk.path)"}|ConvertTo-Json -Compress }else{ $out='{"busy":false,"path":""}' } } }
    '/api/media'{ $out=''; try{ $fp="$($rq.QueryString['p'])"
        if(-not (InRoots $fp) -or -not (Test-Path -LiteralPath $fp -PathType Leaf) -or -not $MediaExt.ContainsKey([IO.Path]::GetExtension($fp).ToLower())){ $rs.StatusCode=404 }
        else{ $fi=New-Object IO.FileInfo $fp; $len=$fi.Length
          $mt=$MediaExt[$fi.Extension.ToLower()]; if(-not $mt){ $mt='application/octet-stream' }
          $st=[long]0; $en=$len-1; $rg="$($rq.Headers['Range'])"; $part=$false
          if($rg -match '^bytes=(\d*)-(\d*)$'){ $part=$true; if($Matches[1] -ne ''){ $st=[long]$Matches[1]; if($Matches[2] -ne ''){ $en=[long]$Matches[2] } }elseif($Matches[2] -ne ''){ $st=[Math]::Max([long]0,$len-[long]$Matches[2]) } }
          if($en -ge $len){ $en=$len-1 }
          if($part -and ($en-$st+1) -gt 2097152){ $en=$st+2097152-1 }
          if($len -eq 0 -or $st -ge $len -or $st -gt $en){ $rs.StatusCode=416; $rs.AddHeader('Content-Range',"bytes */$len") }
          else{ $n=$en-$st+1; $rs.ContentType=$mt; $rs.AddHeader('Accept-Ranges','bytes'); if($part){ $rs.StatusCode=206; $rs.AddHeader('Content-Range',"bytes $st-$en/$len") }; $rs.ContentLength64=$n
            $fs=[IO.File]::Open($fp,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite); try{ [void]$fs.Seek($st,[IO.SeekOrigin]::Begin); $buf=New-Object byte[] 65536; $left=$n
              while($left -gt 0){ $rd=$fs.Read($buf,0,[int][Math]::Min([long]$buf.Length,$left)); if($rd -le 0){ break }; $rs.OutputStream.Write($buf,0,$rd); $left-=$rd } }finally{ $fs.Dispose() } } } }catch{} }
    '/api/openfile'{ try{ $ob=$body|ConvertFrom-Json; $fp="$($ob.path)"; $md="$($ob.mode)"; $out='{"ok":true}'
        # normaliza barras (o Explorer ignora o /select, quando o caminho vem com "/")
        try{ $fp=[IO.Path]::GetFullPath($fp) }catch{}
        if(-not (InRoots $fp)){ $out=@{error=(Tr 'O arquivo nao esta nas pastas de download nem nas da biblioteca.' 'The file is not inside the download or library folders.')}|ConvertTo-Json -Compress }
        elseif(-not (Test-Path -LiteralPath $fp -PathType Leaf)){ $out=@{error=(Tr 'Arquivo nao encontrado (foi movido ou apagado?).' 'File not found (moved or deleted?).')}|ConvertTo-Json -Compress }
        elseif($WIN -and -not $TEST){
          if($md -eq 'open'){ if($MediaExt.ContainsKey([IO.Path]::GetExtension($fp).ToLower())){ Start-Process -FilePath $fp }else{ $out=@{error=(Tr 'Tipo de arquivo nao permitido.' 'File type not allowed.')}|ConvertTo-Json -Compress } }
          else{ $psi=New-Object Diagnostics.ProcessStartInfo 'explorer.exe'; $psi.Arguments='/select,"'+$fp+'"'; $psi.UseShellExecute=$true; [void][Diagnostics.Process]::Start($psi) } }
        elseif(-not $WIN){
          try{ if($md -eq 'open'){ if($MediaExt.ContainsKey([IO.Path]::GetExtension($fp).ToLower())){ Start-Process xdg-open -ArgumentList $fp }else{ $out=@{error=(Tr 'Tipo de arquivo nao permitido.' 'File type not allowed.')}|ConvertTo-Json -Compress } }
            else{ Start-Process xdg-open -ArgumentList (Split-Path -Parent $fp) } }
          catch{ $out=@{error=(ErrTxt (Tr 'abrir o arquivo' 'open the file') $_)|ConvertTo-Json -Compress } } }
      }catch{ L "[abrir] $($_.Exception.Message)"; $out=@{error=(ErrTxt (Tr 'abrir o arquivo' 'open the file') $_)}|ConvertTo-Json -Compress } }
    '/api/notify'{ try{ $nb=$body|ConvertFrom-Json; if($WIN -and -not $TEST){ Bg {param($t,$m) Add-Type -AssemblyName System.Windows.Forms,System.Drawing; $ni=New-Object Windows.Forms.NotifyIcon; $ni.Icon=[Drawing.SystemIcons]::Information; $ni.Visible=$true; $ni.ShowBalloonTip(6000,$t,$m,[Windows.Forms.ToolTipIcon]::Info); Start-Sleep 8; $ni.Dispose() } @("$($nb.title)","$($nb.text)") } }catch{} }
    '/api/poweroff'{ if($WIN -and -not $TEST -and -not $S.running){ try{ Start-Process shutdown.exe -ArgumentList '/s','/t','8' -WindowStyle Hidden }catch{} } }
    '/api/poweroff/cancel'{ if($WIN -and -not $TEST){ try{ Start-Process shutdown.exe -ArgumentList '/a' -WindowStyle Hidden }catch{} } }
    '/api/shortcut'{ $out=@{msg=(Make-Shortcuts $false)}|ConvertTo-Json -Compress }
    '/api/applyupd'{ if($S.running){ $out=@{error=(Tr 'Espere o download terminar para atualizar.' 'Wait for the download to finish before updating.')}|ConvertTo-Json -Compress }
      elseif(-not $S.updText){ $out=@{error=(Tr 'Nao ha atualizacao pronta.' 'No update is ready.')}|ConvertTo-Json -Compress }
      else{ try{ [IO.File]::WriteAllText((J $bin 'app.update.ps1'),$S.updText,(New-Object Text.UTF8Encoding $false)); $out=@{ok=$true}|ConvertTo-Json -Compress
        if($WIN -and -not $TEST -and $S.self){ Start-Process cmd.exe -ArgumentList '/c',('ping 127.0.0.1 -n 4 >nul & start "" "'+$S.self+'"') -WindowStyle Hidden
          $S.stop=$true; $PL.stop=$true; KillTree $S.pid; KillTree $S.lpid; KillTree $S.ipid; $quitSoon=$true } }catch{ $out=@{error=(ErrTxt (Tr 'aplicar a atualizacao' 'apply the update') $_)}|ConvertTo-Json -Compress } } }
    '/api/quit'{ $S.stop=$true; $PL.stop=$true; KillTree $S.pid; KillTree $S.lpid; KillTree $S.ipid; $lst.Stop() }
   }
  }
  if($lst.IsListening -and $out){ $b=[Text.Encoding]::UTF8.GetBytes($out); $rs.ContentType=$ct; try{ if($ct -match 'json|html'){ $rs.AddHeader('Cache-Control','no-store') } }catch{}; $rs.OutputStream.Write($b,0,$b.Length) }
  if($quitSoon){ try{ $rs.Close() }catch{}; $lst.Stop() }
 }catch{
  # Requisicao abortada pelo navegador/fechamento da janela nao e erro do app: nao poluir o log.
  $gone=("$($_.Exception.Message)" -match 'disposed|aborted|Connection reset|The remote|Length Required')
  if(-not $gone){
   $msg=ErrTxt (Tr 'atender uma requisicao da interface' 'handle an interface request') $_
   try{ $rs.StatusCode=500; $rs.ContentType='application/json; charset=utf-8'
    $eb=[Text.Encoding]::UTF8.GetBytes((@{error=$msg}|ConvertTo-Json -Compress)); $rs.OutputStream.Write($eb,0,$eb.Length) }catch{ } } }
 finally{ try{ $rs.Close() }catch{} }
}
try{ Remove-Item ([IO.Path]::Combine($bin,'port.txt')) -ea 0 }catch{}
