#!/usr/bin/env bash
# bootstrap.sh — de cero a mi escritorio: niri + iNiR + esta estética.
#
# Uso:
#   ./bootstrap.sh                # instala lo que falte y aplica mi setup
#   ./bootstrap.sh --ref v3.1.1   # fija la versión de iNiR (recomendado)
#   ./bootstrap.sh -y             # sin preguntas (modo desatendido)
#   ./bootstrap.sh --help
#
# Qué hace, en orden:
#   1. Revisa que niri y quickshell estén instalados (si no, los instala).
#   2. Si no tienes iNiR, lo clona y corre su instalador oficial.
#   3. Aplica mis widgets, popups y configs con install.sh (hace backup).
set -euo pipefail

INIR_REPO="${INIR_REPO:-https://github.com/snowarch/iNiR}"
INIR_REF="${INIR_REF:-}"
SHELL_DIR="$HOME/.config/quickshell/inir"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSUME_YES=0

# Colores solo si la salida es una terminal.
if [ -t 1 ]; then
  B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'
else
  B=; G=; Y=; R=; N=
fi

say()  { printf '\n%s==>%s %s\n' "$B" "$N" "$*"; }
ok()   { printf '    %s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '    %s!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '\n%sERROR:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
bootstrap.sh — instala niri + iNiR y aplica mi estética.

Uso:
  ./bootstrap.sh                Instala lo que falte y aplica mi setup.
  ./bootstrap.sh --ref v3.1.1   Usa esa versión de iNiR (recomendado).
  ./bootstrap.sh -y             No pregunta nada (modo desatendido).
  ./bootstrap.sh --help         Muestra esta ayuda.

Variables opcionales:
  INIR_REF    Igual que --ref.
  INIR_REPO   Otro repo de iNiR (por defecto snowarch/iNiR).

Nada se borra: install.sh hace backup en ~/.config/inir-niri-backup/FECHA-HORA/.
EOF
}

confirm() { # confirm "pregunta" -> 0 = sí (por defecto)
  [ "$ASSUME_YES" = 1 ] && return 0
  printf '    %s [S/n] ' "$1"
  read -r answer || return 0
  case "$answer" in
    n|N|no|No|NO) return 1 ;;
    *) return 0 ;;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -y|--yes)  ASSUME_YES=1; shift ;;
    --ref)     INIR_REF="${2:-}"; [ -n "$INIR_REF" ] || die "--ref necesita un valor (ej: --ref v3.1.1)"; shift 2 ;;
    --ref=*)   INIR_REF="${1#*=}"; shift ;;
    *)         die "Opción desconocida: $1 (usa --help)" ;;
  esac
done

printf '\n%s╭──────────────────────────────────────────────╮%s\n' "$B" "$N"
printf '%s│   inir-niri · instalación paso a paso          │%s\n' "$B" "$N"
printf '%s╰──────────────────────────────────────────────╯%s\n' "$B" "$N"

# ── Comprobaciones básicas ────────────────────────────────────────────────
say "Revisando el terreno"

if [ "$EUID" -eq 0 ]; then
  die "No lo ejecutes como root. Corre ./bootstrap.sh con tu usuario normal."
fi

command -v git >/dev/null 2>&1 || die "Falta git. Instálalo con: sudo pacman -S git"

if ! command -v pacman >/dev/null 2>&1; then
  die "Este script está pensado para Arch/CachyOS.
     En otra distro, sigue la guía de iNiR: https://inir.space/docs/install/"
fi

ok "Usuario: $USER"
ok "Repo:    $SRC"

# ── 1. niri + quickshell ──────────────────────────────────────────────────
say "Paso 1 de 3 · niri y quickshell"

if pacman -Q niri quickshell >/dev/null 2>&1; then
  ok "niri y quickshell ya están instalados"
else
  warn "Falta niri o quickshell (son paquetes del sistema, no se clonan)"
  if confirm "¿Los instalo ahora con pacman? (pedirá tu contraseña)"; then
    sudo pacman -S --needed niri quickshell
    ok "niri y quickshell instalados"
  else
    die "Sin niri no se puede seguir. Instálalos y vuelve a correr el script."
  fi
fi

# ── 2. iNiR ───────────────────────────────────────────────────────────────
say "Paso 2 de 3 · iNiR (el shell)"

if [ -d "$SHELL_DIR/modules" ]; then
  ok "iNiR ya está instalado en $SHELL_DIR"
else
  if [ -n "$INIR_REF" ]; then
    warn "No tienes iNiR. Lo instalo desde $INIR_REPO (versión $INIR_REF)"
  else
    warn "No tienes iNiR. Lo instalo desde $INIR_REPO (última versión)"
  fi

  tmp="$(mktemp -d)"

  if [ -n "$INIR_REF" ]; then
    git clone --depth 1 --branch "$INIR_REF" "$INIR_REPO" "$tmp/iNiR" \
      || die "No pude clonar iNiR (versión $INIR_REF). ¿Existe esa versión?"
  else
    git clone --depth 1 "$INIR_REPO" "$tmp/iNiR" \
      || die "No pude clonar iNiR. Revisa tu conexión a internet."
  fi

  log="$tmp/setup.log"
  if ! ( cd "$tmp/iNiR" && ./setup install -y 2>&1 | tee "$log" ); then
    warn "El instalador de iNiR falló. No apliqué tus configs."
    warn "Registro completo: $log"
    warn "Copia de iNiR:     $tmp/iNiR"
    warn "Si el error menciona makepkg, fakeroot o compilación:"
    warn "  sudo pacman -S --needed base-devel"
    die "Pásame el error de arriba y lo revisamos."
  fi

  if [ ! -d "$SHELL_DIR/modules" ]; then
    warn "El instalador terminó, pero no encuentro $SHELL_DIR/modules"
    warn "Registro: $log"
    die "Prueba a reiniciar la sesión y correr ./bootstrap.sh de nuevo."
  fi

  rm -rf "$tmp"
  ok "iNiR instalado"
fi

# ── 3. Mi estética ────────────────────────────────────────────────────────
say "Paso 3 de 3 · mis widgets, popups y configs"
bash "$SRC/install.sh"

# ── Reinicio del shell ────────────────────────────────────────────────────
if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] && command -v systemctl >/dev/null 2>&1; then
  if systemctl --user restart inir.service 2>/dev/null; then
    ok "iNiR reiniciado"
  else
    warn "No pude reiniciar inir.service (lo harás al entrar a la sesión)"
  fi
else
  warn "Sin sesión de escritorio activa: el shell arrancará en tu próximo login"
fi

printf '\n%s┌──────────────────────────────────────────────┐%s\n' "$B" "$N"
printf '%s│   ¡Listo!                                     │%s\n' "$B" "$N"
printf '%s└──────────────────────────────────────────────┘%s\n' "$B" "$N"

cat <<'EOF'

Si es tu primera vez con niri + iNiR:
  1. Cierra sesión y vuelve a entrar (niri carga tus grupos y su entorno).
  2. En el login, elige la sesión "niri".

Para ver tu escritorio funcionando:
  systemctl --user restart inir.service

Si algo se ve raro:
  inir doctor     # revisa y arregla lo que pueda
  inir logs       # muestra por qué no arrancó

¿Quieres volver atrás? install.sh guardó un backup en:
  ~/.config/inir-niri-backup/FECHA-HORA/
EOF
