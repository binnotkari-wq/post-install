#!/usr/bin/env bash

#####################################################################################
# Kit de post installation, mise en place environnement. Aucune donnée personnelle. #
#####################################################################################

set -ouex pipefail

echo "1. Mise en place des préférences de firefox"
sudo mkdir -p /var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/x86_64/stable/policies
sudo curl -sSL https://raw.githubusercontent.com/binnotkari-wq/post-install/main/config/firefox/policies.json -o /var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/x86_64/stable/policies/policies.json

echo "2. Mise en place du repo Github"
curl -sSL https://raw.githubusercontent.com/binnotkari-wq/scripts/main/git-sync.sh| bash

echo 3. "Installation de brew"
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

echo 4. Installation des flatpaks
# Nota bene : on banni le mode --user pour les flatpaks. Pour une question de sécurité : installation "systeme" pour que personne (ni un utilisateur, ni un logiciel malveillant) ne puisse altérer les outils de base. En installation mode --user, un logiciel malveillant n'a besoin d'aucun privilège particulier pour alterer le contenu d'un flatpak. De plus, l'installation en mode --user n'isole pas plus les flatpaks. En mode système, il sont dans /var/lib, et donc deja en dehors des fichiers de l'OS (aucune pollution).

executer_logique() {
  echo "--- 📦 Installation des applications Flatpak (system-wide) ---"
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak remote-modify --no-filter --enable flathub
  flatpak update -y

  installer_applications_communes
  if grep -qE "silverblue|kinoite|bazzite" /etc/os-release 2>/dev/null; then
    installer_applications_exclusives_atomic
  fi  

  installer_applications_gaming
  if ! grep -qE "bazzite" /etc/os-release 2>/dev/null; then
    installer_applications_gaming_non_bazzite
  fi

  echo "Nettoyage des résidus éventuels"
  flatpak uninstall --unused

  echo "Application des permissions spécifiques"
  sudo flatpak override --user --env=MANGOHUD=1 com.valvesoftware.Steam
  # sudo flatpak override com.usebottles.bottles --user --filesystem=xdg-data/applications
  sudo flatpak override  --talk-name=org.freedesktop.Flatpak --filesystem=home io.github.qwersyk.Newelle
  echo "✅ Flatpaks installés avec succès (system-wide)."
}

installer_applications_gaming_non_bazzite() {
  # Application déjà présentes sur Bazzite en natif
  APPS_GAMING_NON_BAZZITE=(
    # "net.lutris.Lutris"
    "com.valvesoftware.Steam"
    "com.valvesoftware.Steam.CompatibilityTool.Proton-GE"
    "com.valvesoftware.Steam.CompatibilityTool.Boxtron"
    "org.freedesktop.Platform.VulkanLayer.gamescope"
    "org.freedesktop.Platform.VulkanLayer.MangoHud"
  )
  flatpak install --system -y flathub "${APPS_GAMING_NON_BAZZITE[@]}"
}

installer_applications_communes() {
  APPS_COMMUNES=(
    "org.gnome.Calculator"
    "org.gnome.NautilusPreviewer"
    "org.gnome.Characters"
    "org.gnome.TextEditor"
    "org.gnome.Weather"
    "org.gnome.Loupe"
    "org.gnome.Snapshot"
    "org.gnome.baobab"
    "org.gnome.Maps"
    "org.gnome.font-viewer"
    "org.gnome.clocks"
    "org.gnome.Papers"
    "org.gnome.Logs"
    "org.gnome.Decibels"
    "org.gnome.SimpleScan"
    "org.gnome.Music"
    "org.gnome.Showtime"
    "org.gnome.Firmware"
    "org.gnome.SoundRecorder"
    # "org.gnome.DejaDup"
    "org.gnome.Boxes"
    "org.gnome.meld"
    "org.gnome.World.Secrets"

    # Autres applications
    "io.github.kolunmi.Bazaar"
    "org.gnome.gitlab.YaLTeR.VideoTrimmer"
    "org.gnome.gitlab.somas.Apostrophe"
    "com.github.jeromerobert.pdfarranger"
    "com.github.johnfactotum.Foliate"
    "com.github.PintaProject.Pinta"
    "io.github.revisto.drum-machine"
    "io.gitlab.adhami3310.Impression"
    # "net.nokyan.Resources"
    "ca.desrt.dconf-editor"
    "de.haeckerfelix.Shortwave"
    "de.haeckerfelix.Fragments"
    "com.ranfdev.DistroShelf"
    "org.gimp.GIMP"
    "garden.jamie.Morphosis"
    "org.scratchmark.Scratchmark"
    "fr.handbrake.ghb"
    "com.github.tchx84.Flatseal"
    "org.mozilla.firefox"
    "tv.kodi.Kodi"
    "org.libreoffice.LibreOffice"
    "io.github.flattool.Ignition"
    "io.github.flattool.Warehouse"
    "it.mijorus.smile"
    "page.tesk.Refine"
    "org.nickvision.tagger"
    "org.tenacityaudio.Tenacity"

    # Gaming
    "com.heroicgameslauncher.hgl"
    # "com.usebottles.bottles"
  )
  flatpak install --system -y flathub "${APPS_COMMUNES[@]}"
}

installer_applications_exclusives_atomic() {
  APPS_EXCLUSIVES_ATOMIC=(
    # Application à installer, ou déjà installée, en natif sur Nixos
    "io.github.ilya_zlobintsev.LACT"
    "io.github.qwersyk.Newelle"
    # "org.gnome.Extensions"
  )
  flatpak install --system -y flathub "${APPS_EXCLUSIVES_ATOMIC[@]}"
}

executer_logique "$@"
