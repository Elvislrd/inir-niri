#!/usr/bin/env bash
# install.sh — widgets de música/letras + mi configuración de inir y niri
# Hace backup de todo lo que reemplaza; nunca borra nada.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD="$HOME/.config/quickshell/inir/modules"
CFG="$HOME/.config/inir"
NIRI="$HOME/.config/niri"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/.config/inir-niri-backup/$STAMP"

ok=0; skip=0

put() { # put <origen> <destino>
  local from="$1" to="$2"
  mkdir -p "$(dirname "$to")"
  if [ -f "$to" ]; then
    mkdir -p "$BACKUP/$(dirname "${to#$HOME/}")"
    cp -a "$to" "$BACKUP/${to#$HOME/}"
  fi
  if [[ "$from" == *.kdl || "$from" == *.json ]]; then
    sed "s|/home/USERNAME|$HOME|g" "$from" > "$to"
  else
    cp -a "$from" "$to"
  fi
  echo "[+] ${to#$HOME/}"
  ok=$((ok+1))
}

echo "[*] Backup en: $BACKUP"

if [ -d "$MOD" ]; then
  echo "[*] Widgets (código QML)"
  for f in "$SRC"/widgets/visualizer/* "$SRC"/widgets/lyrics/* "$SRC"/widgets/mediaControls/*; do
    put "$f" "$MOD/shared/background/widgets/$(basename "$(dirname "$f")")/$(basename "$f")"
  done
  for f in "$SRC"/common/widgets/*.qml; do
    put "$f" "$MOD/common/widgets/$(basename "$f")"
  done
  for f in "$SRC"/iris/widgets/*.qml; do
    put "$f" "$MOD/iris/widgets/$(basename "$f")"
  done
else
  echo "[!] No encuentro $MOD — se omiten los widgets (¿inir instalado?)"
  skip=$((skip+1))
fi

if [ -d "$CFG" ]; then
  echo "[*] Configuración de inir"
  put "$SRC/config/inir/config.json" "$CFG/config.json"
  for d in widgets desktop-profiles; do
    [ -d "$SRC/config/inir/$d" ] || continue
    while IFS= read -r -d '' f; do
      put "$f" "$CFG/$d/${f#"$SRC/config/inir/$d/"}"
    done < <(find "$SRC/config/inir/$d" -type f -print0)
  done
else
  echo "[!] No encuentro $CFG — se omite la config de inir"
  skip=$((skip+1))
fi

if [ -d "$NIRI" ]; then
  echo "[*] Configuración de niri"
  while IFS= read -r -d '' f; do
    put "$f" "$NIRI/${f#"$SRC/config/niri/"}"
  done < <(find "$SRC/config/niri" -type f -print0)
else
  echo "[!] No encuentro $NIRI — se omite niri"
  skip=$((skip+1))
fi

echo
echo "[*] $ok archivos aplicados, $skip secciones omitidas."
echo "[*] Reinicia:  systemctl --user restart inir.service   y recarga niri (Super+Shift+R)"
echo "[*] Restaurar: copia desde $BACKUP"
