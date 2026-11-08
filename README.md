# Media Downloader

**by Bibinho1999** · [Português](README.pt-BR.md)

Audio and **video downloader** for Windows in a **single file** (`Media-Downloader.bat`). It opens a local web interface, works with YouTube and many other sites, and keeps playlists organized in folders.

> **Status:** built and tested on Linux (backend on PowerShell 7 with the real yt-dlp, interface in Chromium). Tested by the author on Windows only lightly: the `.exe` build, browser cookie reading, process termination and shortcuts depend on Windows and may need adjustments. If something fails, open an *issue* with the error message.

## Features

- **Music or video** from any site supported by yt-dlp (YouTube, Instagram, TikTok, X, Vimeo, SoundCloud, Facebook, Twitch and more).
- **Audio:** MP3, M4A, Opus, FLAC or WAV, with quality choice and embedded cover art/metadata.
- **Video:** MP4 (H.264 + AAC, plays everywhere) or MKV (original, no conversion), with an optional resolution cap.
- **Organized playlists:** one folder named after the playlist (resumes where it stopped), a new folder every time (name + date and time), or no folder. When you paste several links, everything can go into a "Batch date-time" folder.
- **"Playlist: pick tracks" tab:** loads the list, you tick what you want and choose audio or video per track. Modes: all audio, all video, or mixed. Optional Music / Videos subfolders.
- **Resume and history:** remembers what was already downloaded and skips repeats. There is an option to start over.
- **Blocked YouTube videos:** looks for an alternative version and lists what could not be solved, with the reason.
- **Cookies:** rotates between Firefox, Edge, Chrome, Brave, Opera and Vivaldi when one fails or gets blocked. Also accepts a `cookies.txt` next to the program.
- **Always up to date:** yt-dlp is updated every time the program opens (stable or nightly channel). ffmpeg and deno are checked now and then. If a download fails because of an outdated extractor, it updates and retries on its own. Dependency downloads retry with increasing waits and fall back to an alternative address.
- **Language:** opens in English; switch to Portuguese with the selector at the top. Your choice is remembered.
- **Builds an `.exe`:** when you open the `.bat`, it tries to create `Media-Downloader.exe` next to it, with an icon and tray menu. A button in Settings creates Desktop and Start Menu shortcuts.

## How to use

1. Download `Media-Downloader.bat` and put it in a folder of your own (for example `C:\Media-Downloader`).
2. Double-click it. The first time it downloads yt-dlp, ffmpeg and deno (needs internet and access to GitHub).
3. Your browser opens at `http://127.0.0.1:8765/`. Paste the links and click **Download**.
4. Files go to `Downloads` next to the program (changeable in Settings).

If Windows SmartScreen warns you, it is because the file is not signed: click *More info* and *Run anyway*. If your antivirus complains about the `.exe`, use the `.bat`, which does the same thing.

Files created next to the program: `bin\` (helper programs, `settings.json`, download history in `archives\`), `Downloads\` and, if built, the `.exe`.

## Technologies

| Piece | Purpose |
|---|---|
| **Batch (`.bat`) + PowerShell 5.1** | Single file: the `.bat` reads itself and runs the PowerShell part without depending on the script execution policy |
| **PowerShell `HttpListener`** | Local web server (`127.0.0.1` only, ports 8765-8789) with a per-run token and `Host` header check |
| **PowerShell runspaces** | Download, playlist loading and updates in the background without freezing the interface |
| **Plain HTML + CSS + JavaScript** | Interface embedded in the file itself, automatic light/dark theme, English/Portuguese |
| **[yt-dlp](https://github.com/yt-dlp/yt-dlp)** | Extraction and download |
| **[FFmpeg](https://ffmpeg.org/)** (yt-dlp builds) | Conversion, merging audio and video, embedded cover art |
| **[Deno](https://deno.com/)** | Runs the JavaScript that YouTube requires today |
| **C# 5 + `CSharpCodeProvider` (.NET Framework)** | Compiles the `.exe` launcher with a tray icon, right on the user's machine |
| **WScript.Shell** | Shortcut creation |

## How it works inside

- The `.bat` extracts the text after the `###PS###` marker and runs it as a script block.
- Each yt-dlp run uses a temporary UTF-8 config file, avoiding quoting and accent problems on the Windows command line.
- Progress comes from `--progress-template`; finished files from `--exec`.
- The playlist folder name is resolved before the download, because yt-dlp replaces `/` inside template fields.
- The history (`--download-archive`) is kept per link and per format/quality.
- The local API (`/api/...`) is simple and token-protected, leaving room for a browser extension or a standalone app in the future.

## Legal notice

Use it only to download content you have the right to download (yours, public domain, licensed, or authorized). Downloading some content may violate site terms of service or copyright laws in your country. The responsibility for use lies with the user. This project is not affiliated with YouTube, Google or any other site mentioned.

## Credits

All the heavy lifting is done by [yt-dlp](https://github.com/yt-dlp/yt-dlp), [FFmpeg](https://ffmpeg.org/) and [Deno](https://deno.com/), which have their own licenses. This project only orchestrates them.

---

Made by **[Bibinho1999](https://github.com/Bibinho1999)**.
