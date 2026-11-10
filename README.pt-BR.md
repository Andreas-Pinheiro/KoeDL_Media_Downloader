# Media Downloader

**by Andreas-Pinheiro** · [English](README.md)

Baixador de **áudio e vídeo** para Windows, em **um único arquivo** (`Media-Downloader.bat`). Abre uma interface em janela própria, funciona com mais de mil sites e organiza as playlists em pastas.

> **Status:** desenvolvido e testado em ambiente Linux (backend em PowerShell 7 com o yt-dlp real e interface no Chromium). **Ainda não foi testado no Windows.** A geração do `.exe`, a leitura de cookies dos navegadores, o encerramento de processos e a criação de atalhos dependem do Windows e podem precisar de ajustes. Se algo falhar, abra uma *issue* com a mensagem de erro.

## O que faz

- **Música ou vídeo** de qualquer site suportado pelo [yt-dlp](https://github.com/yt-dlp/yt-dlp) (mais de mil; veja a lista de sites dele).
- **Áudio:** MP3, M4A, Opus, FLAC ou WAV, com escolha de qualidade e capa/metadados embutidos.
- **Vídeo:** MP4 (H.264 + AAC, compatível com tudo) ou MKV (original, sem converter), com limite de resolução opcional.
- **Playlists organizadas:** uma pasta com o nome da playlist (retoma de onde parou), uma pasta nova a cada vez (nome + data e hora) ou sem pasta. Ao colar vários links, pode guardar tudo numa pasta "Lote data-hora".
- **Aba "Playlist: escolher faixas":** carrega a lista, você marca o que quer e escolhe áudio ou vídeo em cada faixa. Modos: tudo em áudio, tudo em vídeo ou misturado. Opção de separar em subpastas Músicas e Vídeos.
- **Retomada e histórico:** registra o que já foi baixado e pula repetidos. Há opção de recomeçar do zero.
- **Vídeos bloqueados ou removidos:** procura uma versão alternativa e lista o que não teve solução, com o motivo.
- **Cookies:** rodízio entre Firefox, Edge, Chrome, Brave, Opera e Vivaldi quando um falha ou é bloqueado. Também aceita um `cookies.txt` ao lado do programa.
- **Sempre atualizado:** o yt-dlp é atualizado toda vez que abre (canal estável ou nightly). O ffmpeg e o deno são verificados de tempos em tempos. Se um download falhar por extrator desatualizado, atualiza e tenta de novo sozinho.
- **Atalhos na primeira abertura:** cria sozinho os atalhos da Área de Trabalho e do Menu Iniciar (uma vez) e os aponta para o `.exe` assim que ele é gerado. O Windows não permite fixar na barra de tarefas por programa: clique com o botão direito no atalho > *Fixar na barra de tarefas*.
- **Atualiza a si mesmo:** além do yt-dlp/ffmpeg/deno, o programa consulta este repositório ao abrir e baixa versões novas dele mesmo (vale para o `.bat` e para o `.exe`; dá para desligar em Configurações).
- **Idioma:** abre em inglês; troque para Português no seletor no topo da página. A escolha fica salva para a próxima vez.
- **Gera um `.exe`:** ao abrir o `.bat`, tenta criar `Media-Downloader.exe` ao lado, com ícone e menu na bandeja do sistema. Também cria atalhos na Área de Trabalho e no Menu Iniciar (botão na aba Configurações).

## Como usar

1. Baixe `Media-Downloader.bat` e coloque numa pasta sua (por exemplo `C:\Media-Downloader`).
2. Dê duplo clique. Na primeira vez ele baixa o yt-dlp, o ffmpeg e o deno (precisa de internet e acesso ao GitHub).
3. O app abre em janela própria (Microsoft Edge WebView2, baixado automaticamente; se o runtime do Windows faltar, ele pergunta se deve instalar a última versão). Edge/Chrome em modo app é só alternativa. Cole os links e clique em **Baixar**. A janela lembra tamanho e posição.
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
| **[Deno](https://deno.com/)** | Execução do JavaScript que alguns sites exigem hoje |
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

Feito por **[Andreas-Pinheiro](https://github.com/Andreas-Pinheiro)**.

## Instalador

A primeira execução também gera o `Media-Downloader-Setup.exe` (um instalador: copia o app para a sua pasta de usuário, cria atalhos na Área de Trabalho e no Menu Iniciar, verifica o WebView2 e adiciona a opção de desinstalar em Aplicativos do Windows). Execute uma vez; depois é só usar o atalho.

## Apoie o projeto

<p align="center"><img src="assets/support-banner.png" alt="Apoie o Media Downloader" width="560"></p>

O Media Downloader é gratuito e foi feito com a ajuda do Claude, uma IA da Anthropic. Se ele te ajuda, você pode apoiar de graça:

- ⭐ **Dê uma estrela** no repositório, no topo desta página.
- 🔗 **Compartilhe** com um amigo que também baixa mídia.
- 🐞 **Avise de um problema** na aba [Issues](https://github.com/Andreas-Pinheiro/Media-Downloader/issues).

As mesmas opções (e um botão de café, quando houver) estão dentro do app, na aba **♥ Apoiar**. Apoiar é totalmente opcional.
