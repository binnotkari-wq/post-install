#!/usr/bin/env bash

#####################################################################################
# post installation : configuration OS.                                             #
#####################################################################################

set -oue pipefail

executer_logique () {
  mettre_a_jour_firmwares
  limiter_journaux
  supprimer_flatpak_fedora
  injecter_KARGS_compression_btrfs
  charger_module_ntsync
  parametrer_zram
  parametrer_memoire_virtuelle
  desactiver_service
  masquer_autostarts_gnome
  installer_paquets_systeme
  redemarrer
}

# Sauvegarde un fichier existant en fichier.ext.backup avant modification (schéma A/B, à l'image
# des rootfs A/B des distributions atomiques : une version courante, une version précédente
# garantie fonctionnelle). Le backup est écrasé à chaque exécution : il ne conserve donc que
# l'état d'AVANT le dernier run, pas un historique. Ne fait rien si le fichier n'existe pas
# encore (rien à sauvegarder).
# Usage : backup_fichier <chemin_fichier> [sudo]
#   - passer "sudo" en second argument si le fichier nécessite les droits root pour être lu/copié
backup_fichier () {
  local fichier="$1"
  local besoin_sudo="${2:-}"
 
  if [[ "$besoin_sudo" == "sudo" ]]; then
    if sudo test -f "$fichier"; then
      sudo cp -a "$fichier" "${fichier}.backup"
      echo "  ↳ Backup créé : ${fichier}.backup"
    fi
  else
    if [[ -f "$fichier" ]]; then
      cp -a "$fichier" "${fichier}.backup"
      echo "  ↳ Backup créé : ${fichier}.backup"
    fi
  fi
}

mettre_a_jour_firmwares() {
  echo "==> Mise à jour des firmwares."
  # sudo fwupdmgr refresh
  # sudo fwupdmgr get-updates
  # sudo fwupdmgr update
  echo "✅ Firmwares à jour."
  echo ""
  echo "#####################################################################################"
  echo ""
}

limiter_journaux() {
  echo "==> Limite de l'espace disque occupé par les journaux."
  sudo mkdir -p /etc/systemd/journald.conf.d/
  backup_fichier /etc/systemd/journald.conf.d/00-limit-size.conf sudo
  echo -e "[Journal]\nSystemMaxUse=100M" | sudo tee /etc/systemd/journald.conf.d/00-limit-size.conf
  sudo systemctl restart systemd-journald
  echo "✅ Journaux limités avec succés."
  echo ""
  echo "#####################################################################################"
  echo ""
}

supprimer_flatpak_fedora() {
  echo "==> Nettoyage des flatpaks Fedora."
  mapfile -t REFS_FEDORA < <(flatpak list --system --columns=ref | grep "fedoraproject")
  if ((${#REFS_FEDORA[@]})); then
    sudo flatpak pin --remove "${REFS_FEDORA[@]}" 2>/dev/null || true
  fi
  mapfile -t APPS_FEDORA < <(flatpak list --columns=application,origin | grep -i 'fedora' | awk '{print $1}')
  if ((${#APPS_FEDORA[@]})); then
    sudo flatpak uninstall -y "${APPS_FEDORA[@]}" 2>/dev/null || true
  fi
  sudo flatpak remote-delete --force fedora 2>/dev/null || true
  sudo flatpak remote-delete --force fedora-testing 2>/dev/null || true
  sudo flatpak uninstall --unused
  echo "✅ Flatpaks Fedora supprimés avec succès."
  echo ""
  echo "#####################################################################################"
  echo ""

}

injecter_KARGS_compression_btrfs () {
  echo "==> Mise en place compression BTRFS."
  echo "Karg : compression btrfs zstd:1 (composefs ne prenant pas en compte l'intégralité de /etc/fstab - valade pour toutes les Fedora Atomic et autres dérivés bootc)"
  echo "https://gitlab.com/fedora/ostree/sig/-/work_items/72"
  if ! rpm-ostree kargs | grep -q 'compress=zstd:1'; then
      sudo rpm-ostree kargs --delete="rootflags=subvol=root" --append="rootflags=subvol=root,compress=zstd:1"
      REBOOT_NEEDED=1
      echo "✅ Compression BTRFS mise en place avec succès."
  else
      echo "✅ Compression BTRFS déjà en place."
  fi
  echo ""
  echo "#####################################################################################"
  echo ""
}

charger_module_ntsync () {
  echo "==> Chargement du module NTSYNC au démarrage"
  backup_fichier /etc/modules-load.d/ntsync.conf sudo
  echo "ntsync" | sudo tee /etc/modules-load.d/ntsync.conf sudo
  echo "✅ Module NTSYNC chargé."
  echo ""
  echo "#####################################################################################"
  echo ""
}

parametrer_zram () {
  echo "==> paramétrage de la ZRAM"
  sudo mkdir -p /etc/systemd/zram-generator.conf.d
  backup_fichier /etc/systemd/zram-generator.conf.d/zram-generator_custom.conf sudo
cat <<'EOF' | sudo tee /etc/systemd/zram-generator.conf.d/zram-generator_custom.conf
[zram0]
zram-size = ram * 1.5
compression-algorithm = zstd
swap-priority = 100
EOF
  echo "✅ ZRAM paramétré."
  echo ""
  echo "#####################################################################################"
  echo ""
}

parametrer_memoire_virtuelle () {
  echo "==> paramétrage de la mémoire virtuelle"
  backup_fichier /etc/sysctl.d/99-vm-zram-parameters.conf sudo
cat <<'EOF' | sudo tee /etc/sysctl.d/99-vm-zram-parameters.conf
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
vm.max_map_count=1048576
EOF
  sudo sysctl --system
  echo "✅ Mémoire virtuelle paramétrée."
  echo ""
  echo "#####################################################################################"
  echo ""
}

desactiver_service () {
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
    geoclue.service \
    sssd-kcm.service gssproxy.service \
    pcscd.service

  ### Services utilisateur
  systemctl --user disable \
    tfs-nag.service

  ### Services système : masquage (statique ou activation par socket/dbus)
  sudo systemctl mask \
    geoclue.service \
    gssproxy.service \
    sssd-kcm.service sssd-kcm.socket \
    pcscd.service pcscd.socket

  ### Services utilisateur (--global : pour toute session utilisateur existante et à créer)
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
}

masquer_autostarts_gnome () {
  echo "==> Masquage des applications lancées à l'ouverture de session"
  mkdir -p ~/.config/autostart

  # Liste des application à masquer
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

  # Boucle pour créer les fichiers "Hidden=true"
  for app in "${apps[@]}"; do
    backup_fichier ~/.config/autostart/"$app"
    echo "[Desktop Entry]
Type=Application
Name=$app
Exec=/bin/true
Hidden=true" > ~/.config/autostart/"$app"
  done

  echo "✅ Démarrages automatiques masqués avec succès."
  echo ""
  echo "#####################################################################################"
  echo ""
}

installer_paquets_systeme () {
  echo "==> Layering rpm-ostree (paquets hardware/GUI)"
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
      echo "✅ Paquets système installés avec succès."
  fi
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
