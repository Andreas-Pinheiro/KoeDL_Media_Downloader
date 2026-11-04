# Media Downloader

**by Bibinho1999**

Baixador de **áudio e vídeo** para Windows, em **um único arquivo** (`Media-Downloader.bat`). Abre uma interface no navegador, funciona com YouTube e com muitos outros sites e organiza as playlists em pastas.

> **Status:** desenvolvido e testado em ambiente Linux (backend em PowerShell 7 com o yt-dlp real e interface no Chromium). **Ainda não foi testado no Windows.** A geração do `.exe`, a leitura de cookies dos navegadores, o encerramento de processos e a criação de atalhos dependem do Windows e podem precisar de ajustes. Se algo falhar, abra uma *issue* com a mensagem de erro.

## O que faz

- **Música ou vídeo** de qualquer site suportado pelo yt-dlp (YouTube, Instagram, TikTok, X, Vimeo, SoundCloud, Facebook, Twitch e outros).
- **Áudio:** MP3, M4A, Opus, FLAC ou WAV, com escolha de qualidade e capa/metadados embutidos.
- **Vídeo:** MP4 (H.264 + AAC, compatível com tudo) ou MKV (original, sem converter), com limite de resolução opcional.
- **Playlists organizadas:** uma pasta com o nome da playlist (retoma de onde parou), uma pasta nova a cada vez (nome + data e hora) ou sem pasta. Ao colar vários links, pode guardar tudo numa pasta "Lote data-hora".
- **Aba "Playlist: escolher faixas":** carrega a lista, você marca o que quer e escolhe áudio ou vídeo em cada faixa. Modos: tudo em áudio, tudo em vídeo ou misturado. Opção de separar em subpastas Músicas e Vídeos.
- **Retomada e histórico:** registra o que já foi baixado e pula repetidos. Há opção de recomeçar do zero.
- **Vídeos bloqueados no YouTube:** procura uma versão alternativa e lista o que não teve solução, com o motivo.
- **Cookies:** rodízio entre Firefox, Edge, Chrome, Brave, Opera e Vivaldi quando um falha ou é bloqueado. Também aceita um `cookies.txt` ao lado do programa.
- **Sempre atualizado:** o yt-dlp é atualizado toda vez que abre (canal estável ou nightly). O ffmpeg e o deno são verificados de tempos em tempos. Se um download falhar por extrator desatualizado, atualiza e tenta de novo sozinho.
- **Gera um `.exe`:** ao abrir o `.bat`, tenta criar `Media-Downloader.exe` ao lado, com ícone e menu na bandeja do sistema. Também cria atalhos na Área de Trabalho e no Menu Iniciar (botão na aba Configurações).

## Como usar

1. Baixe `Media-Downloader.bat` e coloque numa pasta sua (por exemplo `C:\Media-Downloader`).
2. Dê duplo clique. Na primeira vez ele baixa o yt-dlp, o ffmpeg e o deno (precisa de internet e acesso ao GitHub).
3. O navegador abre em `http://127.0.0.1:8765/`. Cole os links e clique em **Baixar**.
4. Os arquivos ficam em `Downloads` ao lado do programa (a pasta pode ser trocada em Configurações).

Se o Windows SmartScreen avisar, é porque o arquivo não é assinado: clique em *Mais informações* e *Executar assim mesmo*. Se o antivírus reclamar do `.exe`, use o `.bat`, que faz o mesmo.

Arquivos criados ao lado do programa: `bin\` (programas auxiliares, `settings.json`, histórico de downloads em `archives\`), `Downloads\` e, se gerado, o `.exe`.

## Tecnologias usadas

| Peça | Para quê |
|---|---|
| **Batch (`.bat`) + PowerShell 5.1** | Arquivo único: o `.bat` lê a si mesmo e executa a parte em PowerShell sem depender da política de execução de scripts |
| **PowerShell `HttpListener`** | Servidor web local (somente `127.0.0.1`, portas 8765–8789) com token por execução e verificação do cabeçalho `Host` |
| **Runspaces do PowerShell** | Download, leitura de playlist e atualização em segundo plano, sem travar a interface |
| **HTML + CSS + JavaScript puros** | Interface embutida no próprio arquivo, com tema claro e escuro automático |
| **[yt-dlp](https://github.com/yt-dlp/yt-dlp)** | Extração e download |
| **[FFmpeg](https://ffmpeg.org/)** (builds do yt-dlp) | Conversão, junção de áudio e vídeo e capa embutida |
| **[Deno](https://deno.com/)** | Execução do JavaScript que o YouTube exige hoje |
| **C# 5 + `CSharpCodeProvider` (.NET Framework)** | Compila o lançador `.exe` com ícone na bandeja, direto da máquina do usuário |
| **WScript.Shell** | Criação de atalhos |

## Como funciona por dentro

- O `.bat` extrai o texto depois do marcador `###PS###` e o executa como bloco de script.
- Cada execução do yt-dlp usa um arquivo de configuração temporário em UTF-8. Isso evita problemas de aspas e de acentos na linha de comando do Windows.
- O progresso vem de `--progress-template`; os arquivos concluídos, de `--exec`.
- O nome da pasta da playlist é resolvido antes do download. O yt-dlp troca `/` por outro caractere dentro de campos do modelo de nome, então a pasta não pode ser montada só por ele.
- O histórico (`--download-archive`) é separado por link e por formato/qualidade.
- A API local (`/api/...`) é simples e protegida por token, o que deixa espaço para uma extensão de navegador ou um app com janela própria no futuro.

## Aviso legal

Use apenas para baixar conteúdo que você tem o direito de baixar (seu, de domínio público, com licença que permita ou com autorização). Baixar certos conteúdos pode violar os termos de serviço dos sites ou leis de direitos autorais do seu país. A responsabilidade pelo uso é de quem usa. Este projeto não tem ligação com YouTube, Google ou qualquer outro site citado.

## Créditos

Todo o trabalho pesado é do [yt-dlp](https://github.com/yt-dlp/yt-dlp), do [FFmpeg](https://ffmpeg.org/) e do [Deno](https://deno.com/), que têm suas próprias licenças. Este projeto só os orquestra.

---

Feito por **[Bibinho1999](https://github.com/Bibinho1999)**.
