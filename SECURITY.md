# Security policy / Política de segurança

## Reporting a vulnerability / Como avisar sobre uma falha

**PT:** se você encontrou uma falha de segurança, **não abra uma issue pública** com os detalhes. Use a opção *Security > Report a vulnerability* na aba Security deste repositório (relatório privado do GitHub). Descreva o que aconteceu, como reproduzir e a versão do KoeDL. Responderei assim que possível.

**EN:** if you found a security problem, **do not open a public issue** with the details. Use *Security > Report a vulnerability* on this repository's Security tab (GitHub private report). Describe what happened, how to reproduce it and the KoeDL version. I will answer as soon as I can.

## How KoeDL protects you / O que o KoeDL faz

- The local server listens only on `127.0.0.1` and checks the `Host` header; every request needs a random session token. / O servidor local escuta só em `127.0.0.1`, confere o cabeçalho `Host` e exige um token de sessão aleatório.
- Files can only be opened or played from your download folders. / Só é possível abrir ou tocar arquivos das suas pastas de download.
- Program updates are accepted only if the downloaded file matches the SHA-256 hash published next to it (`KoeDL.bat.sha256`). / As atualizações só são aceitas se o arquivo baixado bater com o hash SHA-256 publicado ao lado dele (`KoeDL.bat.sha256`).
- KoeDL has no analytics and sends nothing about you anywhere. It only contacts the sites you ask it to download from, GitHub (updates, yt-dlp, ffmpeg, deno) and Microsoft (WebView2 and its NuGet package, if missing). / O KoeDL não tem estatísticas e não envia nada sobre você. Só acessa os sites de onde você baixa, o GitHub (atualizações, yt-dlp, ffmpeg, deno) e a Microsoft (WebView2 e o pacote NuGet dele, se faltar).

## Supported versions / Versões com suporte

Only the latest version receives fixes. / Só a versão mais recente recebe correções.
