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

