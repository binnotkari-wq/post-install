#!/usr/bin/env bash
# setup-zram.sh — idempotent zram setup + swap removal
# Testé sur distributions Debian/Ubuntu et RPM (Fedora, RHEL, openSUSE)
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

# ── Suppression système snap ──────────────────────────────────────────
info "==> Suppression des snaps et du framework snap."

while [ "$(snap list | wc -l)" -gt 0 ]; do
    for snap in $(snap list | tail -n +2 | cut -d ' ' -f 1); do
        snap remove --purge "$snap" 2> /dev/null
    done
done

systemctl stop snapd
systemctl disable snapd
systemctl mask snapd
apt purge snapd -y
rm -rf /snap /var/lib/snapd
for userpath in /home/*; do
    rm -rf "$userpath"/snap
done
cat <<-EOF | tee /etc/apt/preferences.d/nosnap.pref
Package: snapd
Pin: release a=*
Pin-Priority: -10
EOF

ok "✅ Snaps et framework snap supprimés avec succès."
