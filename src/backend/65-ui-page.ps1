# ------------------------------------------------------------------ pagina
$tok=[guid]::NewGuid().ToString('N')
$html=@'
@@INCLUDE:src/ui/index.html@@
'@
# mesma pagina com a interface neon (escolhida nas Configuracoes); as duas viajam no arquivo
$htmlN=@'
@@INCLUDE:src/ui/index-neon.html@@
'@
