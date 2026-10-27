#!/usr/bin/env bash
# migrate_home_var.sh
# Migre /home et /var vers des sous-volumes btrfs sur un volume LUKS existant
# Usage : sudo ./migrate_home_var.sh
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
header "Vérifications préalables"

[[ $EUID -eq 0 ]] || die "Ce script doit être exécuté en root (sudo)."

if ! command -v btrfs &>/dev/null; then
    info "btrfs-progs absent — installation en cours..."
    apt-get install -y btrfs-progs \
        || die "Échec de l'installation de btrfs-progs."
    ok "btrfs-progs installé."
else
    ok "btrfs-progs présent."
fi

for cmd in cryptsetup blkid lsblk findmnt mount umount rsync; do
    command -v "$cmd" &>/dev/null || die "Commande manquante : $cmd"
done
ok "Dépendances présentes."

FSTAB="/etc/fstab"
CRYPTTAB="/etc/crypttab"
BACKUP_SUFFIX=".bak-$(date +%Y%m%d-%H%M%S)"
MAPPER_NAME="luks-data"
TMP_BTRFS=$(mktemp -d)
TMP_EXT4=$(mktemp -d)

# Sous-volumes cibles (noms fixes)
SUBVOLS=("home" "var")
declare -A MOUNTPOINTS=( [home]="/home" [var]="/var" )

cleanup() {
    for sv in "${SUBVOLS[@]}"; do
        local mp="${MOUNTPOINTS[$sv]}-migrate-tmp"
        mountpoint -q "$mp" 2>/dev/null && umount "$mp" 2>/dev/null || true
        [[ -d "$mp" ]] && rmdir "$mp" 2>/dev/null || true
    done
    mountpoint -q "$TMP_BTRFS" 2>/dev/null && umount "$TMP_BTRFS" 2>/dev/null || true
    mountpoint -q "$TMP_EXT4"  2>/dev/null && umount "$TMP_EXT4"  2>/dev/null || true
    rmdir "$TMP_BTRFS" 2>/dev/null || true
    rmdir "$TMP_EXT4"  2>/dev/null || true
    if [[ -e "/dev/mapper/${MAPPER_NAME}" ]]; then
        cryptsetup luksClose "$MAPPER_NAME" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# ── Étape 1 : Sélection du volume LUKS ───────────────────────────────
header "Étape 1 — Sélection du volume LUKS contenant le btrfs"

mapfile -t LUKS_DEVS < <(blkid -t TYPE=crypto_LUKS -o device | sort)
[[ ${#LUKS_DEVS[@]} -gt 0 ]] || die "Aucun volume LUKS détecté sur ce système."

# Identifier le LUKS qui héberge /
ROOT_DEV=$(findmnt -n -o SOURCE /)
ROOT_LUKS=""
if [[ "$ROOT_DEV" == /dev/mapper/* ]]; then
    DM_NAME="${ROOT_DEV#/dev/mapper/}"
    for dm in /sys/class/block/"${DM_NAME}"/slaves/*/; do
        SLAVE=$(basename "$dm" 2>/dev/null) || continue
        SLAVE_DEV="/dev/${SLAVE}"
        if blkid -t TYPE=crypto_LUKS "$SLAVE_DEV" &>/dev/null; then
            ROOT_LUKS="$SLAVE_DEV"
        fi
    done
fi

echo ""
echo "  Volumes LUKS détectés :"
echo ""
IDX=1
declare -a CANDIDATES=()
for DEV in "${LUKS_DEVS[@]}"; do
    UUID=$(blkid -s UUID -o value "$DEV" 2>/dev/null || echo "inconnu")
    SIZE=$(lsblk -dn -o SIZE "$DEV" 2>/dev/null || echo "?")
    if [[ "$DEV" == "$ROOT_LUKS" ]]; then
        echo -e "    ${IDX}) $DEV  [UUID: $UUID]  [${SIZE}]  ${YELLOW}← système actuel (/)${NC}"
    else
        echo -e "    ${IDX}) $DEV  [UUID: $UUID]  [${SIZE}]"
        CANDIDATES+=("$IDX:$DEV:$UUID")
    fi
    ((IDX++))
done
echo ""

[[ ${#CANDIDATES[@]} -gt 0 ]] || die "Aucun volume LUKS disponible autre que le système actuel."

declare -a VALID_NUMS=()
for entry in "${CANDIDATES[@]}"; do
    VALID_NUMS+=("${entry%%:*}")
done

while true; do
    ask "Entrez le numéro du volume LUKS btrfs cible [${VALID_NUMS[*]}] :"
    read -r CHOICE
    SELECTED=""
    for entry in "${CANDIDATES[@]}"; do
        if [[ "${entry%%:*}" == "$CHOICE" ]]; then
            SELECTED="$entry"
            break
        fi
    done
    [[ -n "$SELECTED" ]] && break
    warn "Numéro invalide. Choisissez parmi : ${VALID_NUMS[*]}"
done

LUKS_DEV=$(echo "$SELECTED" | cut -d: -f2)
LUKS_UUID=$(echo "$SELECTED" | cut -d: -f3)
echo ""
ok "Volume sélectionné : $LUKS_DEV (UUID: $LUKS_UUID)"

# ── Étape 2 : Ouverture du volume LUKS ───────────────────────────────
header "Étape 2 — Ouverture du volume LUKS"

if [[ -e "/dev/mapper/${MAPPER_NAME}" ]]; then
    ok "Volume déjà ouvert : /dev/mapper/${MAPPER_NAME}"
else
    info "Saisissez la passphrase LUKS pour $LUKS_DEV :"
    cryptsetup luksOpen "$LUKS_DEV" "$MAPPER_NAME" \
        || die "Impossible d'ouvrir le volume LUKS."
    ok "Volume ouvert : /dev/mapper/${MAPPER_NAME}"
fi

FS_TYPE=$(blkid -s TYPE -o value "/dev/mapper/${MAPPER_NAME}" 2>/dev/null || true)
[[ "$FS_TYPE" == "btrfs" ]] \
    || die "Le contenu déchiffré n'est pas un filesystem btrfs (détecté : '${FS_TYPE:-inconnu}')."
ok "Filesystem btrfs confirmé."

# ── Étape 3 : Création des sous-volumes si nécessaire ────────────────
header "Étape 3 — Vérification et création des sous-volumes"

mount -o subvolid=5 "/dev/mapper/${MAPPER_NAME}" "$TMP_BTRFS" \
    || die "Impossible de monter le btrfs (subvolid=5)."

echo ""
info "Sous-volumes existants sur le volume :"
btrfs subvolume list "$TMP_BTRFS" 2>/dev/null | sed 's/^/    /' \
    || echo "    (aucun)"
echo ""

for SV in "${SUBVOLS[@]}"; do
    if btrfs subvolume list "$TMP_BTRFS" 2>/dev/null | grep -q "path ${SV}$"; then
        ok "Sous-volume '${SV}' déjà existant — réutilisation."
    else
        btrfs subvolume create "${TMP_BTRFS}/${SV}" \
            || die "Impossible de créer le sous-volume '${SV}'."
        ok "Sous-volume '${SV}' créé."
    fi
done

umount "$TMP_BTRFS"

# ── Étape 4 : Copie du contenu vers chaque sous-volume ───────────────
header "Étape 4 — Copie du contenu vers les sous-volumes"

for SV in "${SUBVOLS[@]}"; do
    MP="${MOUNTPOINTS[$SV]}"
    TMP_MP="${MP}-migrate-tmp"

    echo ""
    info "── Traitement de ${MP} → sous-volume '${SV}' ──"

    mkdir -p "$TMP_MP"
    mount -o "subvol=${SV},rw" "/dev/mapper/${MAPPER_NAME}" "$TMP_MP" \
        || die "Impossible de monter le sous-volume '${SV}'."

    ITEMS=$(find "$TMP_MP" -mindepth 1 -maxdepth 1 | wc -l)

    if [[ "$ITEMS" -gt 0 ]]; then
        warn "Le sous-volume '${SV}' contient déjà du contenu :"
        ls -la "$TMP_MP" | sed 's/^/    /'
        echo ""
        ask "Sauter la copie vers '${SV}' et réutiliser tel quel ? [O/n] :"
        read -r SKIP_COPY
        if [[ "${SKIP_COPY,,}" != "n" ]]; then
            ok "Copie ignorée pour '${SV}' — contenu existant conservé."
            umount "$TMP_MP"
            rmdir "$TMP_MP"
            continue
        fi
        warn "La copie va écraser/compléter le contenu existant de '${SV}'."
        ask "Confirmer ? [o/N] :"
        read -r CONFIRM_OVERWRITE
        [[ "${CONFIRM_OVERWRITE,,}" == "o" ]] \
            || { info "Copie annulée pour '${SV}'."; umount "$TMP_MP"; rmdir "$TMP_MP"; continue; }
    fi

    info "Copie en cours : ${MP} → sous-volume '${SV}'"
    rsync -aAXv --info=progress2 "${MP}/" "${TMP_MP}/" \
        || die "Échec de la copie rsync pour '${SV}'."
    ok "Copie terminée pour '${SV}'."

    umount "$TMP_MP"
    rmdir "$TMP_MP"
done

# ── Étape 5 : Configuration de /etc/crypttab ─────────────────────────
header "Étape 5 — Configuration de /etc/crypttab"

CRYPTTAB_ENTRY="${MAPPER_NAME}  UUID=${LUKS_UUID}  none  luks,discard"

if grep -q "$LUKS_UUID" "$CRYPTTAB" 2>/dev/null; then
    warn "Entrée déjà présente dans $CRYPTTAB pour UUID $LUKS_UUID :"
    grep "$LUKS_UUID" "$CRYPTTAB" | sed 's/^/    /'
    info "Aucune modification."
else
    cp "$CRYPTTAB" "${CRYPTTAB}${BACKUP_SUFFIX}" 2>/dev/null || true
    echo "" >> "$CRYPTTAB"
    echo "# Volume btrfs — migration home et var" >> "$CRYPTTAB"
    echo "$CRYPTTAB_ENTRY" >> "$CRYPTTAB"
    ok "Entrée ajoutée dans $CRYPTTAB :"
    echo "    $CRYPTTAB_ENTRY"
fi

# ── Étape 6 : Configuration de /etc/fstab ────────────────────────────
header "Étape 6 — Configuration de /etc/fstab"

BTRFS_FS_UUID=$(blkid -s UUID -o value "/dev/mapper/${MAPPER_NAME}" 2>/dev/null)
[[ -n "$BTRFS_FS_UUID" ]] || die "Impossible de lire l'UUID du filesystem btrfs."
info "UUID filesystem btrfs : $BTRFS_FS_UUID"

SYSTEMD_DEV_UNIT="dev-mapper-$(systemd-escape "${MAPPER_NAME}" | sed 's|^dev-mapper-||').device"

cp "$FSTAB" "${FSTAB}${BACKUP_SUFFIX}"
FSTAB_MODIFIED=0

for SV in "${SUBVOLS[@]}"; do
    MP="${MOUNTPOINTS[$SV]}"

    if grep -q "subvol=${SV}" "$FSTAB" 2>/dev/null; then
        warn "Entrée pour subvol=${SV} déjà présente dans $FSTAB :"
        grep "subvol=${SV}" "$FSTAB" | sed 's/^/    /'
        info "Aucune modification pour '${SV}'."
        continue
    fi

    FSTAB_ENTRY="UUID=${BTRFS_FS_UUID}  ${MP}  btrfs  subvol=${SV},defaults,compress=zstd,noatime,x-systemd.requires=${SYSTEMD_DEV_UNIT}  0  0"

    if [[ "$FSTAB_MODIFIED" -eq 0 ]]; then
        echo "" >> "$FSTAB"
        echo "# Volume btrfs — migration home et var" >> "$FSTAB"
        FSTAB_MODIFIED=1
    fi
    echo "$FSTAB_ENTRY" >> "$FSTAB"
    ok "Entrée ajoutée dans $FSTAB pour '${SV}' → ${MP}."
done

# ── Étape 7 : Montage définitif ───────────────────────────────────────
header "Étape 7 — Montage définitif des sous-volumes"

for SV in "${SUBVOLS[@]}"; do
    MP="${MOUNTPOINTS[$SV]}"

    if mountpoint -q "$MP"; then
        warn "${MP} est déjà un point de montage actif — ignoré."
        continue
    fi

    mount "$MP" \
        || die "Échec du montage de ${MP} — vérifiez /etc/fstab."
    ok "${MP} monté (sous-volume '${SV}')."

    echo ""
    info "Contenu de ${MP} après montage :"
    ls -la "$MP" | head -20 | sed 's/^/    /'
    echo ""
done

# ── Étape 8 : Nettoyage des anciens dossiers sur ext4 ────────────────
header "Étape 8 — Nettoyage des anciens dossiers sur la partition ext4"

echo ""
info "Les sous-volumes btrfs sont maintenant montés sur /home et /var."
info "Les anciens dossiers sur la partition ext4 sont masqués mais occupent toujours de l'espace."
echo ""

# Identifier la partition ext4 racine
ROOT_SOURCE=$(findmnt -n -o SOURCE /)
info "Partition ext4 racine détectée : $ROOT_SOURCE"

ask "Monter la partition ext4 en secondaire pour nettoyer les anciens dossiers ? [O/n] :"
read -r DO_CLEAN
if [[ "${DO_CLEAN,,}" == "n" ]]; then
    info "Nettoyage ignoré — les anciens dossiers restent sur l'ext4 (masqués, inoffensifs)."
else
    mount "$ROOT_SOURCE" "$TMP_EXT4" \
        || die "Impossible de monter la partition ext4 en secondaire."
    ok "Partition ext4 montée sur $TMP_EXT4."

    for SV in "${SUBVOLS[@]}"; do
        MP_NAME="${MOUNTPOINTS[$SV]#/}"   # "home" ou "var"
        OLD_DIR="${TMP_EXT4}/${MP_NAME}"

        echo ""
        if [[ ! -d "$OLD_DIR" ]]; then
            info "Dossier $OLD_DIR introuvable — ignoré."
            continue
        fi

        ITEMS=$(find "$OLD_DIR" -mindepth 1 -maxdepth 1 | wc -l)
        if [[ "$ITEMS" -eq 0 ]]; then
            ok "/${MP_NAME} sur ext4 est déjà vide — aucune action."
            continue
        fi

        warn "Contenu de /${MP_NAME} sur l'ext4 (à supprimer) :"
        ls -la "$OLD_DIR" | sed 's/^/    /'
        echo ""
        ask "Supprimer le contenu de /${MP_NAME} sur l'ext4 ? [o/N] :"
        read -r DO_DELETE
        if [[ "${DO_DELETE,,}" == "o" ]]; then
            find "$OLD_DIR" -mindepth 1 -delete \
                || die "Échec de la suppression dans /${MP_NAME} sur l'ext4."
            ok "Ancien /${MP_NAME} nettoyé sur l'ext4."
        else
            info "Suppression ignorée pour /${MP_NAME}."
        fi
    done

    umount "$TMP_EXT4"
    ok "Partition ext4 démontée."
fi

# ── Étape 9 : Mise à jour de l'initramfs ─────────────────────────────
header "Étape 9 — Mise à jour de l'initramfs"

cd /
info "Régénération de l'initramfs (update-initramfs -u -k all)..."
update-initramfs -u -k all \
    || die "Échec de update-initramfs."
ok "Initramfs mis à jour."

# ── Récapitulatif ─────────────────────────────────────────────────────
header "Récapitulatif"

echo -e "
  ${GREEN}Volume LUKS${NC}       : $LUKS_DEV (UUID: $LUKS_UUID)
  ${GREEN}Mapper${NC}            : /dev/mapper/${MAPPER_NAME}
  ${GREEN}Sous-volume home${NC}  : home  →  /home
  ${GREEN}Sous-volume var${NC}   : var   →  /var
  ${GREEN}Déverrouillage${NC}    : passphrase Plymouth (cache automatique systemd)
  ${GREEN}crypttab backup${NC}   : ${CRYPTTAB}${BACKUP_SUFFIX}
  ${GREEN}fstab backup${NC}      : ${FSTAB}${BACKUP_SUFFIX}
"

echo -e "${BOLD}Prêt pour le redémarrage.${NC}"
echo ""
info "En cas de problème au boot : accès recovery GRUB → root shell"
info "  → cryptsetup luksClose ${MAPPER_NAME}"
info "  → commenter les lignes ajoutées dans crypttab et fstab"
info "  → update-initramfs -u && reboot"
echo ""
