#!/usr/bin/env bash

# Services et applications dont le démarrage aitomatique sera désactivé.
# Liste générale : certains seront zbsent de Fedora ou de Bazzite.
# Leur absence ne provoquera pas d'erreur d'éxecution du script ou du système.

set -oue pipefail

echo "==> Désactivation des services et démarrages automatiques"

# Services système : désactivation
sudo systemctl disable \
    NetworkManager-wait-online.service \
    ModemManager.service \
    vboxservice.service \
    sssd.service \
    steamos-manager.service \
    bazzite-tdpfix.service \
    mdmonitor.service \
    vgauthd.service \
    vmtoolsd.service \
    qemu-guest-agent.service \
    virtqemud.service \
    virtlxcd.service \
    virtvboxd.service \
    geoclue.service \
    sssd-kcm.service gssproxy.service \
    pcscd.service || true

# Services utilisateur : désactivation 
systemctl --user disable \
    tfs-nag.service || true

# Services système : masquage (statique ou activation par socket/dbus)
  sudo systemctl mask \
    geoclue.service \
    gssproxy.service \
    sssd-kcm.service sssd-kcm.socket \
    pcscd.service pcscd.socket || true

# Services utilisateur : masquage global (pour toute session utilisateur existante et à créer)
  sudo systemctl --global mask \
    evolution-addressbook-factory.service \
    evolution-calendar-factory.service \
    evolution-alarm-notify.service \
    evolution-source-registry.service \
    evolution-user-prompter.service \
    org.gnome.SettingsDaemon.Smartcard.service \
    org.gnome.SettingsDaemon.Smartcard.target \
    org.gnome.SettingsDaemon.Wwan.service \
    org.gnome.SettingsDaemon.Wwan.target || true


# Autostarts : Masquage des applications lancées à l'ouverture de session
apps=(
    "bazzite-announcement.desktop"
    "geoclue-demo-agent.desktop"
    "orca-autostart.desktop"
    "org.gnome.Evolution-alarm-notify.desktop"
    "spice-vdagent.desktop"
    "steam.desktop"
    "vboxclient.desktop"
    "vmware-user.desktop"
)

mkdir -p ~/.config/autostart

for app in "${apps[@]}"; do
    backup_fichier ~/.config/autostart/"$app"
    echo "[Desktop Entry]
Type=Application
Name=$app
Exec=/bin/true
Hidden=true" > ~/.config/autostart/"$app"
done
