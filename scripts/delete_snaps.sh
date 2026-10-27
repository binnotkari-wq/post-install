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

# Stopper le daemon
systemctl stop snapd
systemctl disable snapd

# Snaps à traiter en dernier, dans l'ordre
SNAPS_LAST=(gtk-common-themes bare core24 snapd)

# Supprimer tous les snaps ordinaires
MAX_ITER=10; iter=0
while snap list 2>/dev/null \
    | awk 'NR>1{print $1}' \
    | grep -qvF "$(printf '%s\n' "${SNAPS_LAST[@]}")" ; do

    snap list 2>/dev/null \
        | awk 'NR>1{print $1}' \
        | grep -vF "$(printf '%s\n' "${SNAPS_LAST[@]}")" \
        | while read -r s; do
            snap remove --purge "$s" || warn "Impossible de supprimer : $s"
          done || true

    (( iter++ )) || true
    (( iter >= MAX_ITER )) && die "Boucle bloquée après $MAX_ITER itérations."
done

# Supprimer les snaps système dans l'ordre
for s in "${SNAPS_LAST[@]}"; do
    snap list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$s" \
        && snap remove --purge "$s" \
        || true
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
