#!/usr/bin/env bash
# install.sh — aplica mis widgets, popups y configs sobre un iNiR ya instalado.
# Hace backup de todo lo que reemplaza; nunca borra nada.
#
# ¿Vienes de cero? Corre primero:  ./bootstrap.sh
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD="$HOME/.config/quickshell/inir/modules"
CFG="$HOME/.config/inir"
NIRI="$HOME/.config/niri"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/.config/inir-niri-backup/$STAMP"

ok=0
skip=0

put() { # put <origen> <destino>
  local from="$1" to="$2"
  mkdir -p "$(dirname "$to")"

  if [ -f "$to" ]; then
    mkdir -p "$BACKUP/$(dirname "${to#"$HOME"/}")"
    cp -a "$to" "$BACKUP/${to#"$HOME"/}"
  fi

  case "$from" in
    *.kdl|*.json)
      sed "s|/home/USERNAME|$HOME|g" "$from" > "$to"
      ;;
    *)
      cp -a "$from" "$to"
      ;;
  esac

  echo "  [+] ${to#"$HOME"/}"
  ok=$((ok + 1))
}

echo
echo "==> Aplicando mi setup de inir + niri"
echo "    Backup de lo que reemplace: $BACKUP"
echo

# ── Comprobación amable ───────────────────────────────────────────────────
if [ ! -d "$MOD" ]; then
  cat <<'EOF'
[!] No encuentro iNiR instalado.

    Este repo es solo la estética (widgets, popups y configs): necesita que
    iNiR y niri ya estén en la máquina.

    La forma fácil, desde cero:

        ./bootstrap.sh

    La forma manual:

        git clone https://github.com/snowarch/iNiR
        cd iNiR && ./setup install
        # luego vuelve aquí y corre ./install.sh
EOF
  exit 1
fi

# ── Widgets y popups (código QML) ─────────────────────────────────────────
echo "==> Widgets y popups (QML)"

for dir in visualizer lyrics mediaControls; do
  for f in "$SRC/widgets/$dir"/*; do
    [ -e "$f" ] || continue
    put "$f" "$MOD/shared/background/widgets/$dir/$(basename "$f")"
  done
done

for f in "$SRC"/popups/bar/*.qml; do
  [ -e "$f" ] || continue
  put "$f" "$MOD/ii/bar/$(basename "$f")"
done
for f in "$SRC"/popups/mediaControls/*.qml; do
  [ -e "$f" ] || continue
  put "$f" "$MOD/shared/mediaControls/$(basename "$f")"
done
for f in "$SRC"/popups/mediaControls/components/*.qml; do
  [ -e "$f" ] || continue
  put "$f" "$MOD/shared/mediaControls/components/$(basename "$f")"
done
for f in "$SRC"/popups/controlPanel/*.qml; do
  [ -e "$f" ] || continue
  put "$f" "$MOD/ii/controlPanel/$(basename "$f")"
done
for f in "$SRC"/common/widgets/*.qml; do
  [ -e "$f" ] || continue
  put "$f" "$MOD/common/widgets/$(basename "$f")"
done
for f in "$SRC"/iris/widgets/*.qml; do
  [ -e "$f" ] || continue
  put "$f" "$MOD/iris/widgets/$(basename "$f")"
done

# ── Configuración de iNiR ─────────────────────────────────────────────────
echo
echo "==> Configuración de iNiR"

if [ -d "$CFG" ]; then
  put "$SRC/config/inir/config.json" "$CFG/config.json"

  for d in widgets desktop-profiles translations; do
    [ -d "$SRC/config/inir/$d" ] || continue
    while IFS= read -r -d '' f; do
      put "$f" "$CFG/$d/${f#"$SRC/config/inir/$d/"}"
    done < <(find "$SRC/config/inir/$d" -type f -print0)
  done

  # Mi config viene de un laptop cuyo monitor se llama eDP-1. Si el tuyo se
  # llama distinto, la barra y los widgets no aparecen. Lo ajusto solo.
  SOURCE_OUTPUT="${SOURCE_OUTPUT:-eDP-1}"

  detect_output() {
    command -v niri >/dev/null 2>&1 || return 0
    niri msg focused-output 2>/dev/null \
      | sed -n 's/^Output "\([^"]*\)".*/\1/p' | head -1
  }

  echo
  echo "==> Monitor"

  current_output="$(detect_output)"

  if [ -z "$current_output" ]; then
    echo "  [!] No pude detectar tu monitor (¿estás dentro de niri?)."
    echo "      Si la barra no aparece, ábrelo en una terminal de niri y corre"
    echo "      ./install.sh otra vez: ajusta el nombre del monitor automáticamente."
  elif [ "$current_output" = "$SOURCE_OUTPUT" ]; then
    echo "  [+] Monitor: $current_output (coincide con la config)"
  else
    echo "  [+] Monitor: $current_output (la config era para $SOURCE_OUTPUT)"
    echo "      Ajustando barra, widgets y perfiles a tu pantalla..."

    monitor_files=("$CFG/config.json" "$CFG/desktop-profiles/profiles.json")
    while IFS= read -r -d '' f; do
      monitor_files+=("$f")
    done < <(find "$CFG/widgets" -type f -print0 2>/dev/null)

    for f in "${monitor_files[@]}"; do
      [ -f "$f" ] || continue
      sed -i "s/$SOURCE_OUTPUT/$current_output/g" "$f"
    done

    echo "  [+] Listo: si tienes varios monitores, revisa Ajustes → Pantallas."
  fi
else
  echo "  [!] No existe $CFG — se omite la config de iNiR"
  skip=$((skip + 1))
fi

# ── Configuración de niri ─────────────────────────────────────────────────
echo
echo "==> Configuración de niri"

if [ -d "$NIRI" ]; then
  while IFS= read -r -d '' f; do
    put "$f" "$NIRI/${f#"$SRC/config/niri/"}"
  done < <(find "$SRC/config/niri" -type f -print0)
else
  echo "  [!] No existe $NIRI — se omite niri (se creará al abrir niri una vez)"
  skip=$((skip + 1))
fi

echo
echo "==> Listo: $ok archivos aplicados, $skip secciones omitidas."
echo
echo "    Para ver los cambios:"
echo "      systemctl --user restart inir.service"
echo "      # y en niri: Super+Shift+R (recargar config)"
echo
echo "    ¿Algo salió mal? Vuelve atrás copiando desde:"
echo "      $BACKUP"
echo
