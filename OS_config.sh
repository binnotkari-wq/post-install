#!/usr/bin/env bash

# Intégrer les optimisation mémoire de tweaks.sh et de l'ancien dichier atomic.sh


#####################################################################################
# Kit de post installation, configuration OS. Aucune donnée personnelle.            #
#####################################################################################

set -oue pipefail

executer_logique () {
  updater_firmwares
  supprimer_flatpak_fedora
  optimiser_OS
  masquer_autostarts_gnome
  installer_paquets_systeme
  redemarrer
}

updater_firmwares() {
  echo "==> Mise à jour des firmwares"
  sudo fwupdmgr refresh
  sudo fwupdmgr get-updates
  sudo fwupdmgr update
  echo "✅ Firmwares à jour."
  echo ""
  echo "#####################################################################################"
  echo ""
}

supprimer_flatpak_fedora() {
  echo "==> Nettoyage des flatpaks Fedora (system-wide)"
  if cat /var/lib/flatpak/repo/config | grep -q "https://registry.fedoraproject.org"; then
    sudo flatpak pin --remove $(flatpak list --system --columns=ref | grep "fedoraproject") 2>/dev/null || true
    sudo flatpak pin --remove runtime/org.fedoraproject.Platform.GL.default/x86_64/f44 || true
    sudo flatpak pin --remove runtime/org.fedoraproject.Platform/x86_64/f44 || true
    sudo flatpak uninstall -y $(flatpak list --columns=application,origin | grep -i 'fedora' | awk '{print $1}') 2>/dev/null || true
    sudo flatpak remote-delete --force fedora 2>/dev/null || true
    sudo flatpak remote-delete --force fedora-testing 2>/dev/null || true
    sudo flatpak uninstall --unused
    sudo rm -rf /var/lib/flatpak/.removed/*
    echo "✅ Flatpaks Fedora supprimés avec succès."
  else
    echo "✅ Flatpaks et repo Fedora déjà supprimés"
  fi
  echo ""
  echo "#####################################################################################"
  echo ""
}

optimiser_OS () {
  echo "==> Mise en place compression BTRFS"
  echo "Karg : compression btrfs zstd:1 (composefs ne prenant pas en compte l'intégralité de /etc/fstab - valade pour toutes les Fedora Atomic et autres dérivés bootc)"
  echo "https://gitlab.com/fedora/ostree/sig/-/work_items/72"
  if ! rpm-ostree kargs | grep -q 'compress=zstd:1'; then
      sudo rpm-ostree kargs --delete="rootflags=subvol=root" --append="rootflags=subvol=root,compress=zstd:1"
      REBOOT_NEEDED=1
      echo "✅ Compression BTRFS mise en place avec succès."
  else
      echo "✅ Compression BTRFS déjà en place."
  fi

  echo "==> Chargement du module NTSYNC au démarrage"
  echo "ntsync" > /usr/lib/modules-load.d/ntsync.conf

  echo "==> paramétrage de la ZRAM"
  sudo mkdir -p /etc/systemd/zram-generator.conf.d
cat <<'EOF' | sudo tee /etc/systemd/zram-generator.conf.d/zram-generator_custom.conf
[zram0]
zram-size = ram * 1.5
compression-algorithm = zstd
swap-priority = 100
EOF

  echo "==> paramétrage de la mémoire virtuelle"
cat <<'EOF' | sudo tee /etc/sysctl.d/99-vm-zram-parameters.conf > /dev/null
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
vm.max_map_count=1048576
EOF

  sudo sysctl --system > /dev/null

  echo "✅ Optimisations appliquées avec succès."
  echo ""
  echo "#####################################################################################"
  echo ""
}

echo "==> Desactivation des services et démarrages automatiques"

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

### Services utilisateur : désactivation classique
sudo systemctl --user disable \
  tfs-nag.service

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

echo "✅ Services désactivés avec succès."
echo ""
echo "#####################################################################################"
echo ""

masquer_autostarts_gnome () {
  echo "==> 7. Masquage des applications lancées à l'ouverture de session"
  mkdir -p ~/.config/autostart

  # Liste des services et application à masquer
  services=(
    "steam.desktop"
    "vboxclient.desktop"
    "vmware-user.desktop"
    "spice-vdagent"
    "orca-autostart.desktop"
    "org.gnome.Evolution-alarm-notify.desktop"
    "bazzite-announcement.desktop"
  )

  # Boucle pour créer les fichiers "Hidden=true"
  for service in "${services[@]}"; do
    echo "[Desktop Entry]
  Type=Application
  Name=$service
  Exec=/bin/true
  Hidden=true" > ~/.config/autostart/"$service"
  done

  echo "✅ Flatpaks installés avec succès."
  echo ""
  echo "#####################################################################################"
  echo ""
}

installer_paquets_systeme () {
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
  echo "✅ Paquets système installés avec succès."
  echo ""
  echo "#####################################################################################"
  echo ""
}

redemarrer () {
  echo "==> Terminé."
  if [[ "${REBOOT_NEEDED:-0}" == "1" ]]; then
      echo "Un reboot est nécessaire (layering rpm-ostree et/ou karg appliqués au prochain déploiement)."
  fi
}

executer_logique "$@"
