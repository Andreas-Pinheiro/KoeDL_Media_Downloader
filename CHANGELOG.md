# Changelog / Histórico de alterações

Formato: versões mais novas primeiro. / Newest versions first.

## 3.15.2
**PT:** corrige o aviso **"Setup ERROR: A propriedade 'v' não foi encontrada"** que aparecia ao abrir o programa em instalações antigas (o registro de dependências de versões anteriores não tinha o campo de versão).
**EN:** fixes the **"Setup ERROR: property 'v' cannot be found"** notice shown on startup on older installs (the dependency record from earlier versions had no version field).

## 3.15.1
**PT:** visual novo: o **logo** do cabeçalho agora tem fundo transparente (o brilho acompanha o desenho) e o **ícone** do programa ficou com a borda limpa, sem serrilhado; o README ganhou um aviso sobre **falso positivo de antivírus** (o `.exe` pode ser marcado por heurística; o `KoeDL.bat` tem resultado melhor, e o SHA-256 permite conferir o arquivo).
**EN:** new look: the header **logo** now has a transparent background (the glow follows the shape) and the program **icon** has clean edges, no jaggies; the README has a note about **antivirus false positives** (the `.exe` may be flagged by heuristics; `KoeDL.bat` scores better, and the SHA-256 lets you verify the file).

## 3.15
**PT:** o vídeo da **Biblioteca** agora aparece assim que você clica nele (antes a tela só mostrava a capa e o vídeo "aparecia" depois de trocar o filtro); a aba ficou bem mais leve (a lista não é mais remontada a cada faixa, a busca espera você parar de digitar, o progresso não redesenha os botões toda hora e listas grandes mostram os primeiros 400 com um aviso); **um lugar só para colar links**: cole na área principal e, se for playlist, a lista de faixas carrega sozinha (link de vídeo comum segue direto para o download); e chegou o **`koedl.sh` para Linux** (x86_64 e aarch64), sem root e sem apt/dnf: ele instala PowerShell, yt-dlp e ffmpeg portáteis na sua pasta, confere o SHA-256 publicado e abre a interface no navegador.
**EN:** the **Library** video now shows the moment you click it (before, the screen kept the cover and the video "appeared" only after switching the filter); the tab is much lighter (the list is no longer rebuilt on every track, search waits for you to stop typing, progress no longer repaints the controls all the time, and big lists show the first 400 with a note); **one place to paste links**: paste into the main box and, if it is a playlist, the track list loads by itself (a plain video link goes straight to the download); and there is now a **`koedl.sh` for Linux** (x86_64 and aarch64), with no root and no apt/dnf: it installs portable PowerShell, yt-dlp and ffmpeg in your own folder, checks the published SHA-256 and opens the interface in your browser.

## 3.14
**PT:** a **Biblioteca** virou um player de verdade: capa animada, barra de progresso, volume, velocidade, aleatório, repetir (todas/uma faixa), tela cheia para vídeo, atalhos (espaço, setas, N/P) e botões do teclado de mídia; dá para **adicionar pastas** com músicas e vídeos que não foram baixados pelo KoeDL (pelo seletor ou colando o caminho); "Mostrar na pasta" ficou mais confiável e mostra a mensagem quando não consegue abrir, com um botão novo para abrir no player do Windows; botão **▶** na fila e no histórico para tocar o que foi baixado direto no KoeDL; mais formatos (wma, m4v, avi); o cabeçalho não estoura mais a largura em telas estreitas; só arquivos de mídia são servidos ao player.
**EN:** the **Library** is now a real player: animated cover, progress bar, volume, speed, shuffle, repeat (all/one), fullscreen for video, shortcuts (space, arrows, N/P) and media keys; you can **add folders** with music and videos that were not downloaded by KoeDL (with the folder picker or by pasting the path); "Show in folder" is more reliable and shows a message when it cannot open, with a new button to open in the Windows player; **▶** button in the queue and history to play what was downloaded right in KoeDL; more formats (wma, m4v, avi); the header no longer overflows on narrow screens; only media files are served to the player.

## 3.13
**PT:** o aviso de versão nova agora aparece logo que o programa abre, antes de baixar ou atualizar o yt-dlp e o ffmpeg — antes, se essa etapa falhasse ou demorasse, o aviso só aparecia no fim (ou não aparecia).
**EN:** the new-version notice now shows as soon as the program opens, before downloading or updating yt-dlp and ffmpeg — before, if that step failed or was slow, the notice only appeared at the end (or not at all).

## 3.12
**PT:** versão de manutenção, sem mudanças visíveis na interface; a publicação automática das releases passou a conferir o `SHA256SUMS.txt` linha a linha, porque a checagem anterior abortava o envio dos arquivos.
**EN:** maintenance release with no visible interface changes; the automatic release publishing now checks `SHA256SUMS.txt` line by line, because the previous check aborted the file upload.

## 3.11
**PT:** aba **Biblioteca** (lista o que você baixou e toca música e vídeo dentro do KoeDL, com busca, filtro, anterior/próxima, aleatório e "tocar a próxima"); o atualizador agora confere o **hash SHA-256** do arquivo com o `SHA256SUMS.txt` da mesma release antes de aceitar a atualização e tem um **plano B** quando a API do GitHub falha; README com o `KoeDL-Setup.exe` como instalação principal, requisitos, FAQ e como conferir o hash; SECURITY, CONTRIBUTING e modelos de issue; atalhos Ctrl+1..5; as notas da release passam a vir deste arquivo; ponteiro do mouse corrigido ao rolar a lista da playlist; novo botão **Limpar** para desistir do link e da playlist carregada; o seletor de faixas não desce mais para o fim da página.
**EN:** new **Library** tab (lists what you downloaded and plays music and video inside KoeDL, with search, filter, previous/next, shuffle and "play next"); the updater now checks the file's **SHA-256** against the `SHA256SUMS.txt` of the same release before accepting an update, with a **fallback** when the GitHub API fails; README with `KoeDL-Setup.exe` as the main install method, requirements, FAQ and how to verify the hash; SECURITY, CONTRIBUTING and issue templates; Ctrl+1..5 shortcuts; release notes now come from this file; mouse pointer fixed when scrolling the playlist list; new **Clear** button to drop the link and the loaded playlist; the track picker no longer slides to the bottom of the page.

## 3.10
**PT:** código-fonte separado em `src/` (o `KoeDL.bat` é gerado por `build/build.py`); atualização automática pelas releases do GitHub; mensagens de erro mais amigáveis; GitHub Actions que gera `KoeDL.bat`, `KoeDL.exe`, `KoeDL-Setup.exe` e o `SHA256SUMS.txt`; licença MIT.
**EN:** source split into `src/` (`KoeDL.bat` is generated by `build/build.py`); self-update through GitHub releases; friendlier error messages; GitHub Actions that builds `KoeDL.bat`, `KoeDL.exe`, `KoeDL-Setup.exe` and `SHA256SUMS.txt`; MIT license.

## 3.9
**PT:** arquivo principal `KoeDL.bat` (o `Media-Downloader.bat` continua só para instalações antigas); fim da janela de permissão da área de transferência; sem o endereço do GitHub aparecendo ao passar o mouse no nome do autor; texto Normal por padrão.
**EN:** main file is now `KoeDL.bat` (`Media-Downloader.bat` stays only for older installs); no more clipboard permission prompt; no GitHub address tooltip on the author name; Normal text size by default.

## 3.8
**PT:** primeira versão que procura atualizações em `KoeDL.bat`.
**EN:** first version that looks for updates in `KoeDL.bat`.

## 3.7
**PT:** novo instalador: escolher a pasta, instalar no sistema ou versão portátil, substituir uma instalação existente mantendo configurações, histórico e fila; aviso de administrador para pastas protegidas; imagem nítida.
**EN:** new installer: choose the folder, install on the system or portable version, replace an existing install keeping settings, history and queue; administrator notice for protected folders; sharper image.

## 3.6
**PT:** o `.exe` é refeito depois de uma atualização (título, bandeja e ícone com o nome novo); botão "Verificar atualizações do programa".
**EN:** the `.exe` is rebuilt after an update (title, tray and icon with the new name); "Check for program updates" button.

## 3.5
**PT:** novo nome **KoeDL** com ícone e banner novos; fila de downloads e histórico; retomar a fila depois de desligar o PC; limite de velocidade, conexões por arquivo, pastas separadas para música e vídeo; notificação, fechar ou desligar o PC ao terminar; temas midnight, sakura e forest; arrastar e soltar links e atalhos de teclado.
**EN:** new name **KoeDL** with new icon and banner; download queue and history; resume the queue after a shutdown; speed limit, connections per file, separate folders for music and video; notification, close or shut down the PC when done; midnight, sakura and forest themes; drag and drop links and keyboard shortcuts.

## 3.4
**PT:** Configurações com menu lateral.
**EN:** Settings with a side menu.

## 3.3
**PT:** botões de apoio (Ko-fi e Pix); Download e Playlist na mesma aba; layout compacto.
**EN:** support buttons (Ko-fi and Pix); Download and Playlist on one tab; compact layout.
