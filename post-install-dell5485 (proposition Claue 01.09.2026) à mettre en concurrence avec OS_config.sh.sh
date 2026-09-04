#!/bin/bash
# Post-install Dell 5485 — Fedora Silverblue vanilla
# Personnalisation minimale : layering ciblé + config /etc mutable + karg
# Idempotent : peut être relancé sans effet de bord.

set -oue pipefail

echo "==> Layering rpm-ostree (paquets liés au hardware/session hôte)"
NEEDED_PKGS=(gamescope zenity)
TO_INSTALL=()
for pkg in "${NEEDED_PKGS[@]}"; do
    if ! rpm -q --quiet "$pkg"; then
        TO_INSTALL+=("$pkg")
    else
        echo "  - $pkg déjà installé, skip"
    fi
done
if ((${#TO_INSTALL[@]})); then
    sudo rpm-ostree install --idempotent "${TO_INSTALL[@]}"
    REBOOT_NEEDED=1
fi



# OK DANS OS CONFIG
echo "==> Karg : compression btrfs forcée en zstd:3 (composefs ignore /etc/fstab pour la racine)"
if ! rpm-ostree kargs | grep -q 'compress-force=zstd:3'; then
    sudo rpm-ostree kargs --append=compress-force=zstd:3
    REBOOT_NEEDED=1
fi




# OK DANS OS CONFIG
echo "==> ntsync au boot"
echo "ntsync" | sudo tee /usr/lib/modules-load.d/ntsync.conf > /dev/null

# OK DANS OS CONFIG
echo "==> sysctl VM / ZRAM tuning"
sudo tee /etc/sysctl.d/99-vm-zram-parameters.conf > /dev/null << 'EOF'
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
vm.max_map_count=1048576
EOF
sudo sysctl --system > /dev/null


# OK DANS OS CONFIG
echo "==> ZRAM generator : zstd, 100% RAM"
sudo tee /etc/systemd/zram-generator.conf > /dev/null << 'EOF'
[zram0]
compression-algorithm=zstd
swap-priority=100
zram-size=100 / 100 * ram
EOF







echo "==> Services système : disable"
sudo systemctl disable \
    NetworkManager-wait-online.service \
    ModemManager.service 2>/dev/null || true

echo "==> Services système : mask"
sudo systemctl mask \
    geoclue.service \
    gssproxy.service \
    sssd-kcm.service sssd-kcm.socket \
    pcscd.service pcscd.socket

echo "==> Services utilisateur : mask (--global)"
sudo systemctl --global mask \
    evolution-addressbook-factory.service \
    evolution-calendar-factory.service \
    evolution-alarm-notify.service \
    evolution-source-registry.service \
    evolution-user-prompter.service \
    org.gnome.SettingsDaemon.Smartcard.service \
    org.gnome.SettingsDaemon.Smartcard.target \
    org.gnome.SettingsDaemon.Wwan.service \
    org.gnome.SettingsDaemon.Wwan.target


# OK DANS OS CONFIG
echo "==> Terminé."
if [[ "${REBOOT_NEEDED:-0}" == "1" ]]; then
    echo "Un reboot est nécessaire (layering rpm-ostree et/ou karg appliqués au prochain déploiement)."
fi

# --- Hors script, à faire manuellement selon besoin ---
# - distrobox : installer via le script officiel (curl ... | sh), pas de layering
# - just, bat, btop, fzf, yt-dlp, tmux, etc. : via distrobox ou brew, pas de layering
# - Vérifier le comportement de Plymouth/amdgpu au boot : ce fix était spécifique
#   au pipeline bootc-image-builder (initrd non régénéré en fin de build).
#   Sur une install vanilla via Anaconda, l'initrd hostonly détecte déjà amdgpu
#   normalement. Ne rien faire sauf si le symptôme est observé après install.
