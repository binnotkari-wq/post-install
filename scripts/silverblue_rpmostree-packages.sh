#!/usr/bin/env bash

# Installe des paquets rpm par rpm ostree. Nécessaire pour ces
# paquets qui doivent êtr eintégré au système de base.

set -euo pipefail

# Arrêt des mises à jour automatiques rpm-ostree pour la durée du script.
sudo rpm-ostree cancel 2>/dev/null || true
sudo systemctl stop rpm-ostreed-automatic.timer rpm-ostreed-automatic.service 2>/dev/null || true
sudo systemctl disable rpm-ostreed-automatic.timer 2>/dev/null || true
gsettings set org.gnome.software download-updates false 2>/dev/null || true
gsettings set org.gnome.software download-updates-notify false 2>/dev/null || true
pkill -x gnome-software 2>/dev/null || true
echo "Mises à jour automatiques stoppées le temps du script."

# Installation des paquets
echo "==> Layering rpm-ostree (paquets hardware/GUI)"
NEEDED_PKGS=(gamescope zenity gnome-shell-extension-dash-to-panel)
TO_INSTALL=()
for pkg in "${NEEDED_PKGS[@]}"; do
    if ! rpm -q --quiet "$pkg"; then
        TO_INSTALL+=("$pkg")
    else
        echo "  - $pkg déjà installé, skip"
    fi
done
if ((${#TO_INSTALL[@]})); then
    sudo rpm-ostree cancel 2>/dev/null || true
    sudo rpm-ostree install --idempotent "${TO_INSTALL[@]}"
    REBOOT_NEEDED=1
    echo "✅ Paquets système installés avec succès."
fi

# Réactivation des mises à jour automatiques rpm-ostree.
sudo systemctl enable --now rpm-ostreed-automatic.timer 2>/dev/null || true
echo "Mises à jour automatiques réactivées."

# Redémarrage du système.
echo "Un redémarrage est nécessaire (layering rpm-ostree et/ou karg appliqués au prochain déploiement)."
echo "Redémarrage dans 10 secondes (Ctrl+C pour annuler)..."
sleep 10
sudo systemctl reboot
