#!/usr/bin/env bash

#####################################################################################
# Kit de post installation, configuration OS. Aucune donnée personnelle.            #
#####################################################################################

set -oue pipefail

echo "1. Mise en place compression BTRFS"
# Explications https://github.com/ublue-os/bazzite/issues/3602
# I believe this is an upstream issue with Fedora Atomic: https://discussion.fedoraproject.org/t/talk-mount-options-are-ignored-in-fedora-atomic-desktops-42/148874/22
# To fix it, you need to add compression to the kernel arguments with rpm-ostree (and reboot to this new deployment): sudo rpm-ostree kargs --delete=rootflags=subvol=root --append=rootflags=subvol=root,compress-force=zstd:1
# Then run disk compression manually to compress all existing files, as only new files will be compressed otherwise: sudo btrfs filesystem defragment -r -v -czstd /var/home
# Toutes les distributions basées sur fedora atomic ont ce défaut : https://gitlab.com/fedora/ostree/sig/-/work_items/72
# Et à chaque fois la solution recommandée est un rpm-ostree kargs

if compress-force=zstd:3 présent dans /etc/fstab
    "✅ Compression BTRFS compress-force=zstd:3 déjà en place."
else 
    # /etc/fstab est ignoré, seule le kargs fonctionne.
    sudo rpm-ostree kargs --delete="rootflags=subvol=root" --append="rootflags=subvol=root,compress-force=zstd:3"

    # /etc/fstab est ignoré après l'installation, et ne semble servir qu'aux montages de anaconda lors de l'installation. Mais pour rester cohérent, on spécifie quand même la compression.
    sudo sed -i 's/compress=zstd:3/compress-force=zstd:3/' /etc/fstab

    # également, marquer directement la compression dans les propriété btrfs de chaque volume (ne fonctionne pas sur / ou /sysroot qui sont en lecteure seul ou composefs)
    sudo btrfs property set /var/home compression zstd
    sudo btrfs property set /var/lib/flatpak compression zstd
    sudo btrfs property set /var/lib/containers compression zstd
    sudo btrfs property set /var/cargo compression zstd
    # NB ces points de montages doivent avoir été affectés à chacun de ces sous-volumes et disques
    echo "✅ Compression BTRFS mise en place avec succès."
fi

echo ""
echo "#####################################################################################"
echo ""



echo "2. Desactivation des services et démarrages automatiques"

# https://claude.ai/chat/e6f562df-2a15-4c9a-b0d1-af616df78281
### Services système : désactivation classique
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
  NetworkManager-wait-online.service \
  geoclue.service \
  sssd-kcm.service gssproxy.service \
  pcscd.service

### Services système : masquage (statique ou activation par socket/dbus)
sudo systemctl mask \
  geoclue.service \
  gssproxy.service \
  sssd-kcm.service sssd-kcm.socket \
  pcscd.service pcscd.socket \

### Services utilisateur (--global : pas de session active pendant le build)
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

echo "✅ Services et démarrages automatiques désactivés avec succès."
echo ""
echo "#####################################################################################"
echo ""



sudo systemctl disable --now  

sudo systemctl disable --now 






systemctl --user disable --now ntfs-nag.service




# Masquage des autostarts gnome
mkdir -p ~/.config/autostart

FILES=(
  orca-autostart.desktop
  geoclue-demo-agent.desktop
  ibus-mozc-launch-xwayland.desktop
  steam.desktop
)

for f in "${FILES[@]}"; do
  src="/etc/xdg/autostart/$f"
  dst="$HOME/.config/autostart/$f"

  if [[ ! -f "$src" ]]; then
    echo "⚠️  $f introuvable dans /etc/xdg/autostart, ignoré."
    continue
  fi

  cp -f "$src" "$dst"

  if grep -q "^Hidden=" "$dst"; then
    sed -i 's/^Hidden=.*/Hidden=true/' "$dst"
  else
    echo "Hidden=true" >> "$dst"
  fi

  echo "✅ $f désactivé (override créé dans ~/.config/autostart/)"
done





