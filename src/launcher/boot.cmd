@echo off
rem KoeDL - by Andreas-Pinheiro - github.com/Andreas-Pinheiro/Media-Downloader
chcp 65001 >nul
title KoeDL - nao feche esta janela
set "SELF=%~f0"
powershell -NoProfile -Command "$f=[IO.File]::ReadAllText($env:SELF,[Text.Encoding]::UTF8);$c=$f.Substring($f.LastIndexOf('###'+'PS###')+8);& ([scriptblock]::Create($c))"
echo.
echo Encerrado. Pressione uma tecla para fechar.
pause >nul
exit /b
