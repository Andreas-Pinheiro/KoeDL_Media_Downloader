#!/usr/bin/env bash
# KoeDL @@VERSION@@ - launcher para Linux (x86_64 e aarch64)
#
# Nao pede root e nao usa apt/dnf/pacman: tudo o que o app precisa fica em
# ~/.local/share/KoeDL (ou em $KOEDL_HOME), junto com os downloads.
# O PowerShell, o yt-dlp e o ffmpeg sao portateis e vem dos releases oficiais.
#
# Uso:  ./koedl.sh            abre a interface no navegador
#       KOEDL_HOME=... ./koedl.sh   guarda tudo em outra pasta
set -u

APPVER='@@VERSION@@'
BASE="${KOEDL_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/KoeDL}"
BIN="$BASE/bin"
mkdir -p "$BIN" || { echo "KoeDL: nao consegui criar $BIN" >&2; exit 1; }

say() { printf '%s\n' "$*"; }
die() { printf '\nKoeDL: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- utilitarios
get() { # get <url> <arquivo>
  if have curl; then curl -fsSL --retry 3 --connect-timeout 20 -o "$2" "$1"
  elif have wget; then wget -q -O "$2" "$1"
  else die "preciso de curl ou wget instalado para baixar as dependencias."; fi
}

sha256of() {
  if have sha256sum; then sha256sum "$1" 2>/dev/null | awk '{print $1}'
  elif have shasum; then shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  elif have openssl; then openssl dgst -sha256 -r "$1" 2>/dev/null | awk '{print $1}'
  else echo ''; fi
}

# confere o hash publicado; sem hash legivel o arquivo e descartado (politica do projeto)
verify() { # verify <arquivo> <soma esperada> <nome>
  local got want="$2"
  got="$(sha256of "$1")"
  if [ -z "$want" ]; then die "nao consegui conferir o SHA-256 de $3 (falta sha256sum/shasum/openssl)." ; fi
  if [ "$got" != "$want" ]; then die "o SHA-256 de $3 nao confere (esperado $want, veio $got). Nada foi instalado." ; fi
}

sum_of() { # sum_of <arquivo de somas> <nome>
  awk -v n="$2" '{ sub(/\r$/, ""); if ($2 == n || $2 == "*"n) { print $1; exit } }' "$1"
}

# ---------------------------------------------------------------- plataforma
case "$(uname -m)" in
  x86_64|amd64) ARCH=x64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) die "arquitetura $(uname -m) nao suportada. Este launcher cobre x86_64 e aarch64." ;;
esac

if have ldd && ldd --version 2>&1 | grep -qi musl; then
  say "Aviso: esta distro usa musl (algo como Alpine). O PowerShell e o yt-dlp oficiais"
  say "sao compilados para glibc, entao provavelmente nao vao rodar aqui."
  say "Se falhar, use uma distro com glibc ou rode o KoeDL dentro de um container."
fi

say "KoeDL $APPVER - Linux/$ARCH"
say "pasta: $BASE"
say ""

# ---------------------------------------------------------------- PowerShell
PWSH=''
if [ -n "${KOEDL_PWSH:-}" ] && [ -x "${KOEDL_PWSH}" ]; then
  PWSH="$KOEDL_PWSH"
elif have pwsh; then
  PWSH="$(command -v pwsh)"
elif [ -x "$BASE/pwsh/pwsh" ]; then
  PWSH="$BASE/pwsh/pwsh"
  # o pacote portatil precisa das proprias libs ao lado; o binario acha sozinho
else
  PWSHVER="${KOEDL_PWSHVER:-7.4.6}"
  case "$ARCH" in
    x64) PWSHARCH=x64 ;;
    arm64) PWSHARCH=arm64 ;;
  esac
  PWSHURL="https://github.com/PowerShell/PowerShell/releases/download/v$PWSHVER/powershell-$PWSHVER-linux-$PWSHARCH.tar.gz"
  say "Baixando o PowerShell $PWSHVER (portatil, ~70 MB)..."
  TMP="$(mktemp -d)" || die "nao consegui criar pasta temporaria."
  get "$PWSHURL" "$TMP/pwsh.tar.gz" || die "nao consegui baixar o PowerShell de $PWSHURL"
  mkdir -p "$BASE/pwsh"
  if ! tar -xzf "$TMP/pwsh.tar.gz" -C "$BASE/pwsh" 2>/dev/null; then
    rm -rf "$TMP"; rm -rf "$BASE/pwsh"
    die "nao consegui extrair o pacote do PowerShell (precisa de tar + gzip)."
  fi
  rm -rf "$TMP"
  chmod +x "$BASE/pwsh/pwsh" 2>/dev/null
  PWSH="$BASE/pwsh/pwsh"
fi
[ -x "$PWSH" ] || die "o PowerShell nao ficou executavel em $PWSH."
say "PowerShell: $PWSH"

# ---------------------------------------------------------------- yt-dlp
YT="$BIN/yt-dlp"
if [ ! -x "$YT" ]; then
  case "$ARCH" in
    x64) YTASSET=yt-dlp_linux ;;
    arm64) YTASSET=yt-dlp_linux_aarch64 ;;
  esac
  YTBASE="https://github.com/yt-dlp/yt-dlp/releases/latest/download"
  say "Baixando o yt-dlp ($YTASSET)..."
  TMP="$(mktemp -d)" || die "nao consegui criar pasta temporaria."
  get "$YTBASE/$YTASSET" "$TMP/yt-dlp" || die "nao consegui baixar o yt-dlp de $YTBASE/$YTASSET"
  get "$YTBASE/SHA2-256SUMS" "$TMP/sums" || die "nao consegui baixar o SHA2-256SUMS do yt-dlp"
  verify "$TMP/yt-dlp" "$(sum_of "$TMP/sums" "$YTASSET")" "yt-dlp"
  chmod +x "$TMP/yt-dlp" && mv -f "$TMP/yt-dlp" "$YT" || die "nao consegui instalar o yt-dlp em $YT"
  rm -rf "$TMP"
  say "yt-dlp: instalado em $YT"
else
  say "yt-dlp: ja instalado ($YT)"
fi

# ---------------------------------------------------------------- ffmpeg
if [ ! -x "$BIN/ffmpeg" ] || [ ! -x "$BIN/ffprobe" ]; then
  case "$ARCH" in
    x64) FFASSET=ffmpeg-master-latest-linux64-gpl.tar.xz ;;
    arm64) FFASSET=ffmpeg-master-latest-linuxarm64-gpl.tar.xz ;;
  esac
  FFBASE="https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest"
  say "Baixando o ffmpeg ($FFASSET, ~100 MB)..."
  TMP="$(mktemp -d)" || die "nao consegui criar pasta temporaria."
  get "$FFBASE/$FFASSET" "$TMP/ff.tar.xz" || die "nao consegui baixar o ffmpeg de $FFBASE/$FFASSET"
  get "$FFBASE/checksums.sha256" "$TMP/sums" || die "nao consegui baixar o checksums.sha256 do ffmpeg"
  verify "$TMP/ff.tar.xz" "$(sum_of "$TMP/sums" "$FFASSET")" "ffmpeg"
  if ! tar -xJf "$TMP/ff.tar.xz" -C "$TMP" 2>/dev/null; then
    rm -rf "$TMP"; die "nao consegui extrair o ffmpeg (precisa de tar com suporte a xz)."
  fi
  FFONE="$(find "$TMP" -type f -name ffmpeg -perm -u+x 2>/dev/null | head -n 1)"
  [ -n "$FFONE" ] || { rm -rf "$TMP"; die "o pacote do ffmpeg nao trouxe o binario."; }
  FFDIR="$(dirname "$FFONE")"
  cp -f "$FFDIR/ffmpeg" "$BIN/ffmpeg" && cp -f "$FFDIR/ffprobe" "$BIN/ffprobe" 2>/dev/null
  chmod +x "$BIN/ffmpeg" "$BIN/ffprobe" 2>/dev/null
  rm -rf "$TMP"
  say "ffmpeg: instalado em $BIN"
else
  say "ffmpeg: ja instalado ($BIN)"
fi

# ---------------------------------------------------------------- o app
APP="$BASE/app.ps1"
awk '/^#__KOEDL_PAYLOAD__$/ { found = 1; next } /^__KOEDL_PAYLOAD_END__$/ { found = 0 } found' "$0" > "$APP" 2>/dev/null
[ -s "$APP" ] || die "nao consegui extrair o programa de dentro deste arquivo ($0)."

export SELF="$APP"
export YTDL_DIR="$BASE"
export PATH="$BIN:$PATH"
export PYTHONUTF8=1

say ""
say "Iniciando o KoeDL (a interface abre no navegador)..."
say "Para fechar: Ctrl+C aqui, ou o botao Quit na interface."
say ""
exec "$PWSH" -NoProfile -File "$APP"

# O programa em PowerShell vem abaixo, dentro de um heredoc que o bash nunca le.
: <<'__KOEDL_PAYLOAD_END__'
#__KOEDL_PAYLOAD__
