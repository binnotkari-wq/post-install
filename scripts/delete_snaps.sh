#!/usr/bin/env bash
# delete_snaps.sh — idempotent
# Spécifique à Ubuntu
# Usage : sudo ./delete_snaps.sh
# --------------------------------------------------------------------

set -euo pipefail

# ── Couleurs ─────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()   { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()     { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()    { echo -e "${RED}[ERREUR]${NC} $*" >&2; exit 1; }
header() { echo -e "\n${BOLD}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
ask()    { echo -e "${YELLOW}[?]${NC}     $*"; }

# ── Vérifications préalables ──────────────────────────────────────────
if ! command -v snap &>/dev/null; then
    ok "snap absent — rien à faire."
    exit 0
fi

# ── Suppression des snaps ─────────────────────────────────────────────
header "Suppression des snaps et du framework snap"

systemctl stop snapd
systemctl disable snapd

MAX_ITER=10; iter=0
while snap list 2>/dev/null | awk 'NR>1{print $1}' | grep -q .; do
    snap list 2>/dev/null | awk 'NR>1{print $1}' | while read -r s; do
        snap remove --purge "$s" || warn "Impossible de supprimer : $s"
    done
    (( iter++ ))
    (( iter >= MAX_ITER )) && die "Boucle bloquée après $MAX_ITER itérations."
done

systemctl mask snapd
apt purge snapd -y
rm -rf /snap /var/lib/snapd
for userpath in /home/*; do
    rm -rf "$userpath/snap"
done

cat <<EOF | tee /etc/apt/preferences.d/nosnap.pref
Package: snapd
Pin: release a=*
Pin-Priority: -10
EOF

ok "Snaps et framework snap supprimés avec succès."
