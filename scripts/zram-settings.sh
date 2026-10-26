#!/usr/bin/env bash
# setup-zram.sh — idempotent zram setup + swap removal
# Testé sur distributions Debian/Ubuntu et RPM (Fedora, RHEL, openSUSE)
# Usage : sudo ./zram-settings.sh
# --------------------------------------------------------------------

set -euo pipefail

# ─── Couleurs ────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
action()  { echo -e "${BOLD}[ACTION]${RESET} $*"; }
err()     { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

# ─── Root ────────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    err "Ce script doit être exécuté en root (sudo)."
    exit 1
fi

if sudo grep -qF 'zram-size = ram * 1.5' /etc/systemd/zram-generator.conf.d/zram-generator_custom.conf 2>/dev/null; then
    ok "zram déjà configuré, rien à faire."
    exit 0
fi

echo -e "\n${BOLD}=== Setup ZRAM + suppression swap ===${RESET}\n"

# ─── Détection du gestionnaire de paquets ────────────────────────────────────
detect_pkg_manager() {
    if command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v zypper &>/dev/null; then
        echo "zypper"
    else
        err "Gestionnaire de paquets non supporté (ni dnf, apt-get, ni zypper trouvés)."
        exit 1
    fi
}

PKG_MGR=$(detect_pkg_manager)
info "Gestionnaire de paquets détecté : ${BOLD}${PKG_MGR}${RESET}"

# ─── Fonction de sauvegarde de fichier de configuration ────────────────────────────────────
backup_fichier () {
    local fichier="$1"
    local besoin_sudo="${2:-}"

    local backup="${fichier}.backup"

    if [[ "$besoin_sudo" == "sudo" ]]; then
        # Ne faire le backup que si le backup n'existe pas déjà
        if test -f "$fichier" && ! sudo test -f "$backup"; then
            cp -a "$fichier" "$backup"
            ok "  ↳ Backup créé : ${backup}"
        fi
    else
        if [[ -f "$fichier" ]] && [[ ! -f "$backup" ]]; then
            cp -a "$fichier" "$backup"
            ok "  ↳ Backup créé : ${backup}"
        fi
    fi
}

# ─── Installation de zram-generator ──────────────────────────────────────────
ZRAM_PKG="zram-generator"

install_if_missing() {
    case "$PKG_MGR" in
        dnf)
            # dnf est idempotent : pas besoin de tester avant
            info "Installation/vérification de ${ZRAM_PKG} via dnf..."
            dnf install -y "$ZRAM_PKG"
            ;;
        apt)
            # apt aussi, mais on teste quand même pour un message propre
            if dpkg -s systemd-zram-generator &>/dev/null 2>&1; then
                ok "systemd-zram-generator déjà installé."
            else
                info "Installation de systemd-zram-generator via apt..."
                apt-get install -y systemd-zram-generator
            fi
            ZRAM_PKG="systemd-zram-generator"
            ;;
        zypper)
            if rpm -q "$ZRAM_PKG" &>/dev/null; then
                ok "${ZRAM_PKG} déjà installé."
            else
                info "Installation de ${ZRAM_PKG} via zypper..."
                zypper install -y "$ZRAM_PKG"
            fi
            ;;
    esac
}

install_if_missing

# ─── Configuration zram-generator ────────────────────────────────────────────
ZRAM_CONF="/etc/systemd/zram-generator.conf.d/zram-generator_custom.conf"

mkdir -p /etc/systemd/zram-generator.conf.d
backup_fichier "$ZRAM_CONF"

action "Création de ${ZRAM_CONF}..."
cat > "$ZRAM_CONF" << 'CONF'
[zram0]
zram-size = ram * 1.5
compression-algorithm = zstd
swap-priority = 100
CONF
ok "${ZRAM_CONF} créé."

# ─── Activation de zram ───────────────────────────────────────────────────────
systemctl daemon-reload

if swapon --show | grep -q "zram"; then
    ok "ZRAM déjà actif comme swap."
else
    action "Activation de zram..."
    # Tente le démarrage du service systemd-zram-setup
    if systemctl start "systemd-zram-setup@zram0.service" 2>/dev/null; then
        ok "zram0 activé via systemd."
    else
        warn "Service systemd non disponible, tentative manuelle..."
        modprobe zram 2>/dev/null || true
        sleep 1
        if [[ -b /dev/zram0 ]]; then
            zramctl --find --size "$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 2 ))K" --algorithm zstd
            mkswap /dev/zram0
            swapon -p 100 /dev/zram0
            ok "zram0 activé manuellement."
        else
            err "Impossible d'activer zram0."
            exit 1
        fi
    fi
fi

# ─── Détection et suppression du swap existant ───────────────────────────────
echo ""
info "Analyse du swap actif (hors zram)..."

FOUND_SWAP=0

# Swapfiles
while IFS= read -r swapfile; do
    FOUND_SWAP=1
    action "Désactivation du swapfile : ${swapfile}"
    swapoff "$swapfile"
    if [[ -f "$swapfile" ]]; then
        rm -f "$swapfile"
        ok "Swapfile ${swapfile} supprimé."
    fi
    # Nettoyage fstab
    if grep -qs "$swapfile" /etc/fstab; then
        sed -i "\|${swapfile}|d" /etc/fstab
        ok "Entrée fstab pour ${swapfile} supprimée."
    fi
done < <(swapon --show=NAME --noheadings | grep -v "zram" | grep "^/" | grep -v "^/dev/")

# Partitions swap
while IFS= read -r part; do
    FOUND_SWAP=1
    warn "Partition swap détectée : ${BOLD}${part}${RESET}"
    action "Désactivation de la partition swap : ${part}"
    swapoff "$part"
    ok "Partition ${part} désactivée comme swap."
    echo ""
    echo -e "${YELLOW}┌─────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${YELLOW}│ ACTION MANUELLE REQUISE pour ${part}${RESET}"
    echo -e "${YELLOW}│                                                             │${RESET}"
    echo -e "${YELLOW}│  1. Supprimer ou commenter la ligne dans /etc/fstab :       │${RESET}"
    echo -e "${YELLOW}│     sudo nano /etc/fstab                                    │${RESET}"
    echo -e "${YELLOW}│     → chercher 'swap' ou '${part}'           │${RESET}"
    echo -e "${YELLOW}│                                                             │${RESET}"
    echo -e "${YELLOW}│  2. Supprimer/reformater la partition si souhaité :         │${RESET}"
    echo -e "${YELLOW}│     sudo fdisk /dev/sdX  (ou gdisk, cfdisk...)              │${RESET}"
    echo -e "${YELLOW}│     → supprimer la partition ${part}         │${RESET}"
    echo -e "${YELLOW}│                                                             │${RESET}"
    echo -e "${YELLOW}│  ⚠ Ne pas toucher à une partition LVM ou chiffrée          │${RESET}"
    echo -e "${YELLOW}│    sans vérification préalable.                             │${RESET}"
    echo -e "${YELLOW}└─────────────────────────────────────────────────────────────┘${RESET}"
    echo ""
done < <(swapon --show=NAME --noheadings | grep -v "zram" | grep "^/dev/")

if [[ $FOUND_SWAP -eq 0 ]]; then
    ok "Aucun swap non-zram actif trouvé."
fi

# ─── Résumé final ─────────────────────────────────────────────────────────────
echo ""
info "État du swap après opération :"
swapon --show
echo ""
ok "Terminé."
