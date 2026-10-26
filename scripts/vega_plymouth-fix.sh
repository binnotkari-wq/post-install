#!/usr/bin/env bash

set -euo pipefail

echo "==> Intégration Plymouth/amdgpu (GPU AMD Vega intégré, ex: Picasso/Vega 8)"
echo "==> pour invite graphique de saisie du mot de passe LUKS."

INITRAMFS=$(sudo ls -t /boot/ostree/*/initramfs-*.img 2>/dev/null | head -1)

if [[ -n "$INITRAMFS" ]]; then
    TMPOUT=$(mktemp)
    sudo lsinitrd "$INITRAMFS" 2>/dev/null > "$TMPOUT"
    if grep -q 'amdgpu' "$TMPOUT"; then
        rm -f "$TMPOUT"
        echo "amdgpu déjà présent dans l'initramfs, rien à faire."
        exit 0
    fi
    rm -f "$TMPOUT"
fi

backup_fichier () {
    local fichier="$1"
    local besoin_sudo="${2:-}"

    local backup="${fichier}.backup"

    if [[ "$besoin_sudo" == "sudo" ]]; then
        # Ne faire le backup que si le backup n'existe pas déjà
        if sudo test -f "$fichier" && ! sudo test -f "$backup"; then
            sudo cp -a "$fichier" "$backup"
            echo "  ↳ Backup créé : ${backup}"
        fi
    else
        if [[ -f "$fichier" ]] && [[ ! -f "$backup" ]]; then
            cp -a "$fichier" "$backup"
            echo "  ↳ Backup créé : ${backup}"
        fi
    fi
}

# Arrêt des mises à jour automatiques rpm-ostree pour la durée du script.
sudo rpm-ostree cancel 2>/dev/null || true
sudo systemctl stop rpm-ostreed-automatic.timer rpm-ostreed-automatic.service 2>/dev/null || true
sudo systemctl disable rpm-ostreed-automatic.timer 2>/dev/null || true
gsettings set org.gnome.software download-updates false 2>/dev/null || true
gsettings set org.gnome.software download-updates-notify false 2>/dev/null || true
pkill -x gnome-software 2>/dev/null || true
echo "Mises à jour automatiques stoppées le temps du script."

# Intégration à l'initramfs
DRACUT_CONF="/etc/dracut.conf.d/amdgpu-early.conf"
PLYMOUTH_CONF="/etc/plymouth/plymouthd.conf"


# Fichier dracut : force le chargement précoce du driver amdgpu dans l'initramfs
if ! sudo grep -qE 'force_drivers\+?=.*amdgpu' "${DRACUT_CONF}" 2>/dev/null; then
    backup_fichier "${DRACUT_CONF}" sudo
    echo 'force_drivers+=" amdgpu "' | sudo tee "${DRACUT_CONF}" >/dev/null
    echo "  ↳ ${DRACUT_CONF} créé/mis à jour."
else
    echo "  ↳ ${DRACUT_CONF} déjà en place."
fi

# Config Plymouth : thème bgrt + UseSimpledrm=1 (valeur numérique, pas "true")
if sudo test -f "${PLYMOUTH_CONF}"; then
    backup_fichier "${PLYMOUTH_CONF}" sudo
fi
if ! sudo grep -qE '^\[Daemon\]' "${PLYMOUTH_CONF}" 2>/dev/null \
   || ! sudo grep -qE '^Theme=bgrt' "${PLYMOUTH_CONF}" 2>/dev/null \
   || ! sudo grep -qE '^UseSimpledrm=1' "${PLYMOUTH_CONF}" 2>/dev/null; then
cat <<'EOF' | sudo tee "${PLYMOUTH_CONF}" >/dev/null
[Daemon]
Theme=bgrt
UseSimpledrm=1
EOF

    echo "  ↳ ${PLYMOUTH_CONF} créé/mis à jour."
else
    echo "  ↳ ${PLYMOUTH_CONF} déjà en place."
fi


# rpm-ostree initramfs-etc --track= ne régénère pas fiablement en mode générique :
# on untrack au cas où un tracking résiduel existerait, puis on force l'inclusion
# via dracut -I (seule méthode confirmée fonctionnelle, cf. message d'erreur
# "initramfs regeneration and /etc overlay not compatible; use dracut arg -I instead").
for f in "${DRACUT_CONF}" "${PLYMOUTH_CONF}"; do
    if rpm-ostree status | grep -q "${f}"; then
        sudo rpm-ostree initramfs-etc --untrack="${f}" 2>/dev/null || true
    fi
done
sudo rpm-ostree cancel 2>/dev/null || true
sudo rpm-ostree initramfs --enable \
    --arg=-I --arg="${DRACUT_CONF}" \
    --arg=-I --arg="${PLYMOUTH_CONF}"
echo "initramfs régénéré."

# Réactivation des mises à jour automatiques rpm-ostree.
sudo systemctl enable --now rpm-ostreed-automatic.timer 2>/dev/null || true
echo "Mises à jour automatiques réactivées."

echo "✅ Correctif Plymouth/amdgpu appliqué (nouveau déploiement, reboot nécessaire)."