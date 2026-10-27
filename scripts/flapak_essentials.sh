#!/usr/bin/env bash
# flapak_essentials.sh — idempotent 
# Testé sur distributions Debian/Ubuntu/Fedora/Atomic
# Usage : ./flapak_essentials.sh
# --------------------------------------------------------------------

set -euo pipefail

# ─── Couleurs ───────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
header()  { echo -e "\n${BOLD}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
action()  { echo -e "${BOLD}[ACTION]${RESET} $*"; }
err()     { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

# ─── Execution ──────────────────────────────────────────────────────
header "Installation des applications Flatpak essentielles"

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install flathub org.mozilla.firefox
flatpak install flathub io.github.kolunmi.Bazaar

ok "✅ Applications Flatpaks essentielles installés avec succès."
