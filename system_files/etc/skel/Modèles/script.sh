#!/usr/bin/env bash
# script.sh — idempotent 
# Testé sur distributions (nom de la distribution)
# Usage : ./script.sh
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

# Ressources :
# https://github.com/onceupon/Bash-Oneliner
# https://tldp.org/LDP/Bash-Beginners-Guide/html/

# Exemples utiles :

# if and else loop for string matching
if [[ "$c" == "read" ]]; then outputdir="seq"; else outputdir="write" ; fi

# Test if myfile contains the string 'test':
if grep -q hello myfile; then echo -e "file contains the string!" ; fi

# Test if mydir is a directory, change to it and do other stuff:
if cd mydir; then
  echo 'some content' >myfile
else
  echo >&2 "Fatal error. This script requires mydir."
fi


# Test if file exist
if [ -e 'filename' ]
then
  echo -e "file exists!"
fi
