# ------------------------------------------------------------------ pagina
$tok=[guid]::NewGuid().ToString('N')
$html=@'
@@INCLUDE:src/ui/index.html@@
'@
