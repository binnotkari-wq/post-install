#!/usr/bin/env bash
# integrate_btrfs_home.sh
# Intègre un volume LUKS/btrfs existant comme /home sur Ubuntu
# Usage : sudo ./integrate_btrfs_home.sh
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

for cmd in cryptsetup blkid lsblk mount umount rsync; do
    command -v "$cmd" &>/dev/null || die "Commande manquante : $cmd"
done
ok "Dépendances présentes."

CRYPTTAB="/etc/crypttab"
FSTAB="/etc/fstab"
BACKUP_SUFFIX=".bak-$(date +%Y%m%d-%H%M%S)"
MAPPER_NAME="luks-btrfs-home"
TMP_MOUNT=$(mktemp -d)
cleanup() {
    mountpoint -q "$TMP_MOUNT" && umount "$TMP_MOUNT" 2>/dev/null || true
    rmdir "$TMP_MOUNT" 2>/dev/null || true
}
trap cleanup EXIT

# ── Étape 1 : Nettoyage préalable du /home Ubuntu ────────────────────
header "Étape 1 — Nettoyage préalable de /home"

echo ""
info "Le subvolume btrfs va être monté sur /home."
info "Tout contenu déjà présent dans /home sera masqué sous le point de montage."
echo ""
info "Contenu actuel de /home :"
ls -la /home | sed 's/^/    /'
echo ""

ITEMS_COUNT=$(find /home -mindepth 1 -maxdepth 1 | wc -l)

if [[ "$ITEMS_COUNT" -gt 0 ]]; then
    echo -e "${YELLOW}  ┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}  │  ACTION MANUELLE REQUISE avant de continuer                 │${NC}"
    echo -e "${YELLOW}  │                                                             │${NC}"
    echo -e "${YELLOW}  │  /home contient du contenu qui sera masqué après montage.   │${NC}"
    echo -e "${YELLOW}  │  Supprimez-le manuellement dans un autre terminal :         │${NC}"
    echo -e "${YELLOW}  │                                                             │${NC}"
    echo -e "${YELLOW}  │    sudo find /home -mindepth 1 -delete                      │${NC}"
    echo -e "${YELLOW}  │                                                             │${NC}"
    echo -e "${YELLOW}  │  Revenez ici et appuyez sur Entrée pour continuer.          │${NC}"
    echo -e "${YELLOW}  └─────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    ask "Appuyez sur Entrée une fois /home nettoyé (ou Ctrl+C pour annuler)..."
    read -r

    ITEMS_AFTER=$(find /home -mindepth 1 -maxdepth 1 | wc -l)
    if [[ "$ITEMS_AFTER" -gt 0 ]]; then
        warn "/home contient encore des éléments :"
        ls -la /home | sed 's/^/    /'
        ask "Continuer quand même ? Le contenu sera simplement masqué. [o/N] :"
        read -r FORCE
        [[ "${FORCE,,}" == "o" ]] || die "Opération annulée."
    else
        ok "/home est vide — on continue."
    fi
else
    ok "/home est déjà vide — aucune action requise."
fi

# ── Étape 2 : Sélection du volume LUKS ───────────────────────────────
header "Étape 2 — Sélection du volume LUKS à intégrer"

mapfile -t LUKS_DEVS < <(blkid -t TYPE=crypto_LUKS -o device | sort)
[[ ${#LUKS_DEVS[@]} -gt 0 ]] || die "Aucun volume LUKS détecté sur ce système."

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

declare -a VALID_NUMS=()
for entry in "${CANDIDATES[@]}"; do
    VALID_NUMS+=("${entry%%:*}")
done
[[ ${#CANDIDATES[@]} -gt 0 ]] || die "Aucun volume LUKS disponible autre que le système actuel."

while true; do
    ask "Entrez le numéro du volume LUKS à intégrer comme /home [${VALID_NUMS[*]}] :"
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

# ── Étape 3 : Ouverture du volume LUKS ───────────────────────────────
header "Étape 3 — Ouverture du volume LUKS"

if [[ -e "/dev/mapper/${MAPPER_NAME}" ]]; then
    ok "Volume déjà ouvert : /dev/mapper/${MAPPER_NAME}"
else
    info "Saisissez la passphrase LUKS pour $LUKS_DEV :"
    cryptsetup luksOpen "$LUKS_DEV" "$MAPPER_NAME" \
        || die "Impossible d'ouvrir le volume LUKS."
    ok "Volume ouvert : /dev/mapper/${MAPPER_NAME}"
fi

# ── Étape 4 : Détection du subvolume btrfs ───────────────────────────
header "Étape 4 — Détection du subvolume btrfs"

FS_TYPE=$(blkid -s TYPE -o value "/dev/mapper/${MAPPER_NAME}" 2>/dev/null || true)
[[ "$FS_TYPE" == "btrfs" ]] \
    || die "Le contenu déchiffré n'est pas un filesystem btrfs (détecté : '${FS_TYPE:-inconnu}')."

mount -o subvolid=5,ro "/dev/mapper/${MAPPER_NAME}" "$TMP_MOUNT" \
    || die "Impossible de monter le btrfs (subvolid=5)."

BTRFS_SUBVOLS=$(btrfs subvolume list "$TMP_MOUNT" 2>/dev/null)
echo ""
info "Subvolumes présents :"
echo "$BTRFS_SUBVOLS" | sed 's/^/    /'
echo ""

DEFAULT_SUBVOL=""
if echo "$BTRFS_SUBVOLS" | grep -q "path home$"; then
    DEFAULT_SUBVOL="home"
fi

umount "$TMP_MOUNT"

while true; do
    if [[ -n "$DEFAULT_SUBVOL" ]]; then
        ask "Nom du subvolume btrfs à monter sur /home [défaut : $DEFAULT_SUBVOL] :"
        read -r INPUT_SUBVOL
        BTRFS_SUBVOL="${INPUT_SUBVOL:-$DEFAULT_SUBVOL}"
    else
        ask "Nom du subvolume btrfs à monter sur /home :"
        read -r BTRFS_SUBVOL
    fi
    [[ -n "$BTRFS_SUBVOL" ]] || { warn "Nom vide."; continue; }

    mount -o subvolid=5,ro "/dev/mapper/${MAPPER_NAME}" "$TMP_MOUNT"
    if btrfs subvolume list "$TMP_MOUNT" | grep -q "path ${BTRFS_SUBVOL}$"; then
        umount "$TMP_MOUNT"
        ok "Subvolume '${BTRFS_SUBVOL}' confirmé."
        break
    else
        umount "$TMP_MOUNT"
        warn "Subvolume '${BTRFS_SUBVOL}' introuvable. Réessayez."
    fi
done

# ── Étape 5 : Copie du dossier utilisateur si absent du subvolume ─────
header "Étape 5 — Vérification et copie du dossier utilisateur"

# Détecter les utilisateurs normaux (UID >= 1000, shell valide, hors nobody)
declare -a NORMAL_USERS=()
while IFS=: read -r uname _ uid _ _ uhome ushell; do
    [[ "$uid" -ge 1000 ]] || continue
    [[ "$ushell" == */false ]] && continue
    [[ "$ushell" == */nologin ]] && continue
    [[ "$uname" == "nobody" ]] && continue
    NORMAL_USERS+=("$uname:$uhome")
done < /etc/passwd

[[ ${#NORMAL_USERS[@]} -gt 0 ]] || { info "Aucun utilisateur normal détecté — étape ignorée."; }

if [[ ${#NORMAL_USERS[@]} -gt 0 ]]; then
    echo ""
    echo "  Utilisateurs détectés :"
    echo ""
    IDX=1
    declare -a USER_CANDIDATES=()
    for entry in "${NORMAL_USERS[@]}"; do
        uname="${entry%%:*}"
        uhome="${entry##*:}"
        echo -e "    ${IDX}) ${uname}  [home actuel : ${uhome}]"
        USER_CANDIDATES+=("$IDX:$uname:$uhome")
        ((IDX++))
    done
    echo ""

    declare -a USER_VALID_NUMS=()
    for entry in "${USER_CANDIDATES[@]}"; do
        USER_VALID_NUMS+=("${entry%%:*}")
    done

    while true; do
        ask "Entrez le numéro de l'utilisateur à vérifier/copier [${USER_VALID_NUMS[*]}] :"
        read -r UCHOICE
        USELECTED=""
        for entry in "${USER_CANDIDATES[@]}"; do
            if [[ "${entry%%:*}" == "$UCHOICE" ]]; then
                USELECTED="$entry"
                break
            fi
        done
        [[ -n "$USELECTED" ]] && break
        warn "Numéro invalide. Choisissez parmi : ${USER_VALID_NUMS[*]}"
    done

    TARGET_USER=$(echo "$USELECTED" | cut -d: -f2)
    TARGET_HOME=$(echo "$USELECTED" | cut -d: -f3)
    TARGET_USERNAME=$(basename "$TARGET_HOME")

    echo ""
    info "Utilisateur sélectionné : $TARGET_USER (home : $TARGET_HOME)"

    # Monter le subvolume en lecture-écriture pour vérifier et éventuellement copier
    mount -o "subvol=${BTRFS_SUBVOL},rw" "/dev/mapper/${MAPPER_NAME}" "$TMP_MOUNT" \
        || die "Impossible de monter le subvolume btrfs en lecture-écriture."

    if [[ -d "${TMP_MOUNT}/${TARGET_USERNAME}" ]]; then
        ok "Dossier '${TARGET_USERNAME}' déjà présent dans le subvolume — aucune copie nécessaire."
        echo ""
        info "Contenu de ${TMP_MOUNT}/${TARGET_USERNAME} :"
        ls -la "${TMP_MOUNT}/${TARGET_USERNAME}" | head -20 | sed 's/^/    /'
    else
        warn "Dossier '${TARGET_USERNAME}' absent du subvolume btrfs."
        echo ""
        if [[ -d "$TARGET_HOME" ]]; then
            info "Source disponible : $TARGET_HOME"
            echo ""
            ask "Copier $TARGET_HOME vers le subvolume btrfs maintenant ? [O/n] :"
            read -r DO_COPY
            if [[ "${DO_COPY,,}" != "n" ]]; then
                info "Copie en cours (rsync -a) : $TARGET_HOME → ${TMP_MOUNT}/${TARGET_USERNAME}"
                rsync -a --info=progress2 "$TARGET_HOME/" "${TMP_MOUNT}/${TARGET_USERNAME}/" \
                    || die "Échec de la copie rsync."
                # Conserver la propriété
                TARGET_UID=$(id -u "$TARGET_USER" 2>/dev/null || echo "")
                TARGET_GID=$(id -g "$TARGET_USER" 2>/dev/null || echo "")
                if [[ -n "$TARGET_UID" && -n "$TARGET_GID" ]]; then
                    chown -R "${TARGET_UID}:${TARGET_GID}" "${TMP_MOUNT}/${TARGET_USERNAME}/"
                    ok "Propriété définie : ${TARGET_UID}:${TARGET_GID}"
                fi
                ok "Copie terminée : ${TMP_MOUNT}/${TARGET_USERNAME}/"
            else
                info "Copie ignorée — le dossier utilisateur sera absent de /home au premier boot."
            fi
        else
            warn "Source $TARGET_HOME introuvable — copie impossible."
            info "Le dossier utilisateur sera absent de /home au premier boot."
        fi
    fi

    umount "$TMP_MOUNT"
fi

# ── Étape 6 : Configuration de /etc/crypttab ─────────────────────────
header "Étape 6 — Configuration de /etc/crypttab"

CRYPTTAB_ENTRY="${MAPPER_NAME}  UUID=${LUKS_UUID}  none  luks,discard"

if grep -q "$LUKS_UUID" "$CRYPTTAB" 2>/dev/null; then
    warn "Entrée déjà présente dans $CRYPTTAB pour UUID $LUKS_UUID :"
    grep "$LUKS_UUID" "$CRYPTTAB" | sed 's/^/    /'
    info "Aucune modification."
else
    cp "$CRYPTTAB" "${CRYPTTAB}${BACKUP_SUFFIX}" 2>/dev/null || true
    echo "" >> "$CRYPTTAB"
    echo "# Volume btrfs existant — home intégré" >> "$CRYPTTAB"
    echo "$CRYPTTAB_ENTRY" >> "$CRYPTTAB"
    ok "Entrée ajoutée dans $CRYPTTAB :"
    echo "    $CRYPTTAB_ENTRY"
fi

# ── Étape 7 : Configuration de /etc/fstab ────────────────────────────
header "Étape 7 — Configuration de /etc/fstab"

BTRFS_FS_UUID=$(blkid -s UUID -o value "/dev/mapper/${MAPPER_NAME}" 2>/dev/null)
[[ -n "$BTRFS_FS_UUID" ]] \
    || die "Impossible de lire l'UUID du filesystem btrfs."
info "UUID filesystem btrfs : $BTRFS_FS_UUID"

SYSTEMD_DEV_UNIT="dev-mapper-$(systemd-escape --path "/dev/mapper/${MAPPER_NAME}" | sed 's|dev-mapper-||').device"

FSTAB_ENTRY="UUID=${BTRFS_FS_UUID}  /home  btrfs  subvol=${BTRFS_SUBVOL},defaults,compress=zstd,noatime,x-systemd.requires=${SYSTEMD_DEV_UNIT}  0  0"

if grep -q "$BTRFS_FS_UUID" "$FSTAB" 2>/dev/null; then
    warn "Entrée déjà présente dans $FSTAB pour UUID $BTRFS_FS_UUID :"
    grep "$BTRFS_FS_UUID" "$FSTAB" | sed 's/^/    /'
    info "Aucune modification."
else
    cp "$FSTAB" "${FSTAB}${BACKUP_SUFFIX}"
    echo "" >> "$FSTAB"
    echo "# Volume btrfs existant — home intégré" >> "$FSTAB"
    echo "$FSTAB_ENTRY" >> "$FSTAB"
    ok "Entrée ajoutée dans $FSTAB."
fi

# ── Étape 8 : Mise à jour de l'initramfs ─────────────────────────────
header "Étape 8 — Mise à jour de l'initramfs"

info "Régénération de l'initramfs (update-initramfs -u -k all)..."
update-initramfs -u -k all \
    || die "Échec de update-initramfs."
ok "Initramfs mis à jour."

# ── Étape 9 : Test de montage ─────────────────────────────────────────
header "Étape 9 — Test de montage"

ask "Tester le montage de /home maintenant (recommandé) ? [O/n] :"
read -r TEST_MOUNT

if [[ "${TEST_MOUNT,,}" != "n" ]]; then
    mount /home \
        || die "Échec du montage de /home — vérifiez /etc/fstab."
    echo ""
    info "Contenu de /home après montage :"
    ls -la /home | sed 's/^/    /'
    echo ""
    ok "Montage réussi."
    ask "Démonter /home pour laisser le boot le gérer proprement ? [O/n] :"
    read -r DO_UMOUNT
    if [[ "${DO_UMOUNT,,}" != "n" ]]; then
        umount /home
        ok "/home démonté."
    fi
else
    info "Test ignoré."
fi

# ── Récapitulatif ─────────────────────────────────────────────────────
header "Récapitulatif"

echo -e "
  ${GREEN}Volume LUKS${NC}      : $LUKS_DEV (UUID: $LUKS_UUID)
  ${GREEN}Mapper${NC}           : /dev/mapper/${MAPPER_NAME}
  ${GREEN}Subvolume btrfs${NC}  : ${BTRFS_SUBVOL}
  ${GREEN}Point de montage${NC} : /home
  ${GREEN}Déverrouillage${NC}   : passphrase Plymouth (cache automatique systemd)
  ${GREEN}crypttab backup${NC}  : ${CRYPTTAB}${BACKUP_SUFFIX}
  ${GREEN}fstab backup${NC}     : ${FSTAB}${BACKUP_SUFFIX}
"

echo -e "${BOLD}Prêt pour le redémarrage.${NC}"
echo ""
info "En cas de problème au boot : accès recovery GRUB → root shell"
info "  → cryptsetup luksClose ${MAPPER_NAME}"
info "  → commenter les lignes ajoutées dans crypttab et fstab"
info "  → update-initramfs -u && reboot"
echo ""
