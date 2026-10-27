#!/usr/bin/env bash
# base_tools.sh — idempotent 
# Testé sur distributions Debian/Ubuntu
# Usage : ./base_tools.sh
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

# ─── Execution ──────────────────────────────────────────────────────
header "Installation des outils de base"
sudo apt install just git distrobox curl btrfs-compsize btrfs-progs flatpak
ok "✅ Outils de base installés avec succès."
