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

