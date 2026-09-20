#!/usr/bin/env bash

# Karg : compression btrfs zstd:1 (composefs ne prenant pas en compte l'intégralité
# de /etc/fstab - valade pour toutes les Fedora Atomic et autres dérivés bootc).
# https://gitlab.com/fedora/ostree/sig/-/work_items/72

set -euo pipefail

# Arrêt des mises à jour automatiques rpm-ostree pour la durée du script.
sudo rpm-ostree cancel 2>/dev/null || true
sudo systemctl stop rpm-ostreed-automatic.timer rpm-ostreed-automatic.service 2>/dev/null || true
sudo systemctl disable rpm-ostreed-automatic.timer 2>/dev/null || true
gsettings set org.gnome.software download-updates false 2>/dev/null || true
gsettings set org.gnome.software download-updates-notify false 2>/dev/null || true
pkill -x gnome-software 2>/dev/null || true
echo "Mises à jour automatiques stoppées le temps du script."

# Injection KARG : mise en place compression BTRFS.
sudo rpm-ostree cancel 2>/dev/null || true
sudo rpm-ostree kargs --delete="rootflags=subvol=root" --append="rootflags=subvol=root,compress=zstd:1"
echo "✅ Compression BTRFS mise en place avec succès."

# Réactivation des mises à jour automatiques rpm-ostree.
sudo systemctl enable --now rpm-ostreed-automatic.timer 2>/dev/null || true
echo "Mises à jour automatiques réactivées."

# Redémarrage du système.
echo "Un redémarrage est nécessaire (layering rpm-ostree et/ou karg appliqués au prochain déploiement)."
echo "Redémarrage dans 10 secondes (Ctrl+C pour annuler)..."
sleep 10
sudo systemctl reboot
