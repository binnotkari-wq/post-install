#!/usr/bin/env bash
# Allègement commun Ubuntu / Fedora / Bazzite
# Idempotent, tolérant aux services absents, sans suppression de paquets
set -euo pipefail

echo "==> [1/5] Désactivation des services système"
sudo systemctl disable \
  NetworkManager-wait-online.service \
  ModemManager.service \
  avahi-daemon.service \
  sssd.service \
  sssd-kcm.service \
  gssproxy.service \
  pcscd.service \
  geoclue.service \
  sysstat.service \
  kdump-tools.service \
  mdmonitor.service \
  cloud-init.service \
  cloud-config.service \
  cloud-final.service \
  cloud-init-local.service \
  cloud-init-main.service \
  cloud-init-network.service \
  vboxservice.service \
  vgauthd.service \
  vmtoolsd.service \
  qemu-guest-agent.service \
  virtqemud.service \
  virtlxcd.service \
  virtvboxd.service \
  steamos-manager.service \
  bazzite-tdpfix.service \
  openvpn.service \
  || true

# Décommenter si pas d'abonnement Ubuntu Pro
# sudo systemctl disable ubuntu-advantage.service || true
# sudo systemctl disable ubuntu-advantage-desktop-daemon.service || true

# Décommenter si on préfère gérer les updates manuellement sur Ubuntu
# sudo systemctl disable unattended-upgrades.service || true

echo "==> [2/5] Masquage des services activables par D-Bus/socket"
sudo systemctl mask \
  ModemManager.service \
  avahi-daemon.service \
  avahi-daemon.socket \
  sssd.service \
  sssd-kcm.service \
  sssd-kcm.socket \
  gssproxy.service \
  pcscd.service \
  pcscd.socket \
  geoclue.service \
  cloud-init.service \
  vboxservice.service \
  vgauthd.service \
  vmtoolsd.service \
  openvpn.service \
  || true

# Décommenter si pas d'abonnement Ubuntu Pro
# sudo systemctl mask ubuntu-advantage.service || true
# sudo systemctl mask ubuntu-advantage-desktop-daemon.service || true

# Décommenter si on préfère gérer les updates manuellement sur Ubuntu
# sudo systemctl mask unattended-upgrades.service || true

echo "==> [3/5] Masquage global des services utilisateur (Evolution, GNOME inutiles)"
sudo systemctl --global mask \
  evolution-addressbook-factory.service \
  evolution-calendar-factory.service \
  evolution-alarm-notify.service \
  evolution-source-registry.service \
  evolution-user-prompter.service \
  org.gnome.SettingsDaemon.Smartcard.service \
  org.gnome.SettingsDaemon.Smartcard.target \
  org.gnome.SettingsDaemon.Wwan.service \
  org.gnome.SettingsDaemon.Wwan.target \
  || true

echo "==> [4/5] Masquage des autostarts"
mkdir -p ~/.config/autostart
apps=(
  "org.gnome.Evolution-alarm-notify.desktop"
  "spice-vdagent.desktop"
  "orca-autostart.desktop"
  "geoclue-demo-agent.desktop"
  "bazzite-announcement.desktop"
  "steam.desktop"
  "vboxclient.desktop"
  "vmware-user.desktop"
)
for app in "${apps[@]}"; do
  printf '[Desktop Entry]\nType=Application\nName=%s\nExec=/bin/true\nHidden=true\n' \
    "$app" > ~/.config/autostart/"$app"
done

# Désactiver ibus comme méthode de saisie GNOME
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'fr')]"
gsettings set org.gnome.desktop.input-sources mru-sources "[('xkb', 'fr')]"

echo "==> [5/5] Désactivation extension ding (GNOME)"
gnome-extensions disable ding@rastersoft.com || true

echo "✅ Terminé — redémarrage recommandé pour valider."
