#!/usr/bin/env bash

# Nota bene : on banni le mode --user pour les flatpaks. Pour une question de sécurité : installation "systeme" pour que personne (ni un utilisateur, ni un logiciel malveillant) ne puisse altérer les outils de base. En installation mode --user, un logiciel malveillant n'a besoin d'aucun privilège particulier pour alterer le contenu d'un flatpak. De plus, l'installation en mode --user n'isole pas plus les flatpaks. En mode système, il sont dans /var/lib, et donc deja en dehors des fichiers de l'OS (aucune pollution).

executer_logique() {
  echo "--- 📦 Installation des applications Flatpak (system-wide) ---"
  ajouter_repo_flathub
  installer_applications_gaming
  if ! grep -qE "bazzite" /etc/os-release 2>/dev/null; then
    installer_applications_gaming_non_bazzite
  fi
  installer_applications_communes
  if grep -qE "silverblue|kinoite|bazzite" /etc/os-release 2>/dev/null; then
    installer_applications_exclusives_atomic
  fi
  nettoyer_et_appliquer_permissions
  echo "✅ Flatpaks installés avec succès (system-wide)."
}


#====================================
# FONCTIONS
#====================================

ajouter_repo_flathub() {
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak remote-modify --no-filter --enable flathub
  flatpak update -y
# flatpak remote-add --if-not-exists --subset=verified --title='Flathub Verified' flathub-verified https://dl.flathub.org/repo/flathub.flatpakrepo
}

installer_applications_gaming_non_bazzite() {
  # Application déjà présentes sur Bazzite en natif
  APPS_GAMING_NON_BAZZITE=(
    "net.lutris.Lutris"
    "com.valvesoftware.Steam"
    "com.valvesoftware.Steam.CompatibilityTool.Proton-GE"
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

    # Gaming
    "com.heroicgameslauncher.hgl"
    "com.usebottles.bottles"
  )
  flatpak install --system -y flathub "${APPS_COMMUNES[@]}"
}

installer_applications_exclusives_atomic() {
  APPS_EXCLUSIVES_ATOMIC=(
    "io.github.ilya_zlobintsev.LACT" # si Nixos : doit être installé en natif
    "io.github.qwersyk.Newelle" # si Nixos : doit être installé en natif
    "org.gnome.Extensions" # si Nixos : dest déjà installé en natif (et ne peux pas être desinstallé)
  )
  flatpak install --system -y flathub "${APPS_EXCLUSIVES_ATOMIC[@]}"
}

nettoyer_et_appliquer_permissions() {
  echo "Nettoyage des résidus éventuels"
  flatpak uninstall --unused

  echo "Application des permissions spécifiques flatpaks gaming"
  flatpak override --user --env=MANGOHUD=1 com.valvesoftware.Steam
  flatpak override com.usebottles.bottles --user --filesystem=xdg-data/applications
}


# =============================================================================
# EXECUTION
# =============================================================================

executer_logique "$@"
