#!/usr/bin/env bash
# install.sh — widgets de música y letras para inir + niri
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD="$HOME/.config/quickshell/inir/modules"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/.config/inir-music-widgets-backup/$STAMP"

if [ ! -d "$MOD" ]; then
  echo "[!] No encuentro $MOD — ¿inir está instalado?"
  exit 1
fi

put() {
  local rel="$1"
  if [ ! -f "$MOD/$rel" ]; then
    echo "[!] sin destino, se omite: $rel"
    return 0
  fi
  mkdir -p "$BACKUP/$(dirname "$rel")"
  cp -a "$MOD/$rel" "$BACKUP/$rel"
  cp -a "$SRC/$rel" "$MOD/$rel"
  echo "[+] $rel"
}

echo "[*] Backup: $BACKUP"
echo "[*] Widgets de escritorio"
for f in widgets/visualizer/* widgets/lyrics/* widgets/mediaControls/*; do
  put "shared/background/$f"
done

echo "[*] Componentes del visualizador (cava)"
for f in common/widgets/CavaProcess.qml common/widgets/CavaSpectrum.qml \
         common/widgets/CavaVisualizer.qml common/widgets/CavaWavyLine.qml \
         common/widgets/AudioVisualizerLayer.qml; do
  put "$f"
done

echo "[*] Caras Iris (lyrics / now playing)"
for f in iris/widgets/IrisLyricsFace.qml iris/widgets/IrisNowPlayingFace.qml; do
  put "$f"
done

echo
echo "[*] Reinicia el shell:  systemctl --user restart inir.service"
echo "[*] Luego activa los widgets: escritorio → editar widgets → Visualizer / Lyrics / Media"
echo "[*] Listo."
