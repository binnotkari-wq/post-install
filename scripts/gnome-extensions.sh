#!/usr/bin/env bash
# gnome-extensions.sh — idempotent 
# Testé sur distribution ubuntu
# Usage : ./gnome-extensions.sh
# --------------------------------------------------------------------

set -euo pipefail

# ─── Couleurs ───────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
header()  { echo -e "\n${BOLD}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
action()  { echo -e "${BOLD}[ACTION]${RESET} $*"; }
err()     { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { echo -e "${RED}[ERREUR]${NC} $*" >&2; exit 1; }
ask()     { echo -e "${YELLOW}[?]${NC}     $*"; }

# ─── Execution ──────────────────────────────────────────────────────
header "Paramétrage des extensions gnome."

EXT_UUID="dash-to-panel@jderose9.github.com"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_UUID"

info "Installation de l'extension dash to panel"
LATEST=$(curl -s https://api.github.com/repos/home-sweet-gnome/dash-to-panel/releases/latest \
  | grep "browser_download_url.*zip" | cut -d'"' -f4)

curl -L "$LATEST" -o /tmp/dash-to-panel.zip
mkdir -p "$EXT_DIR"
unzip -o /tmp/dash-to-panel.zip -d "$EXT_DIR"

gnome-extensions enable "$EXT_UUID"

info "Désactivation des extensions éventuellement préinstallées."
gnome-extensions disable ding@rastersoft.com
gnome-extensions disable ubuntu-dock@ubuntu.com

# A conserver : extension d'interfaces autorisations et messages des applications snap
# gnome-extensions disable snapd-prompting@canonical.com
# gnome-extensions disable snapd-search-provider@canonical.com

# A conserver : pratiques au quotidien
# gnome-extensions disable tiling-assistant@ubuntu.com
# gnome-extensions disable ubuntu-appindicators@ubuntu.com
# gnome-extensions disable web-search-provider@ubuntu.com

ok "Extensions gnome paramétrées."
info "Si dash to panel ne s'est pas activé, redémarrer la session et exécuter gnome-extensions enable dash-to-panel@jderose9.github.com"