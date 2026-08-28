#!/usr/bin/env bash

# installer   gnome-shell-extension-dash-to-panel en userland


#####################################################################################
# Kit de post installation, mise en place environnement. Aucune donnée personnelle. #
#####################################################################################

set -oue pipefail

echo "1. Mise en place des préférences de firefox"
sudo mkdir -p /var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/x86_64/stable/policies
sudo curl -sSL https://raw.githubusercontent.com/binnotkari-wq/post-install/main/system_files/etc/firefox/policies/policies.json -o /var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/x86_64/stable/policies/policies.json
sudo mkdir -p /etc/firefox/policies
sudo curl -sSL https://raw.githubusercontent.com/binnotkari-wq/post-install/main/system_files/etc/firefox/policies/policies.json -o /etc/firefox/policies/policies.json
echo "✅ Préférences Firefox mises en place avec succès."
echo ""
echo "#####################################################################################"
echo ""

echo "2. Mise en place du repo Github"
curl -sSL https://raw.githubusercontent.com/binnotkari-wq/scripts/main/git-sync.sh| bash
echo "✅ Repo Github mis en place avec succès."
echo ""
echo "#####################################################################################"
echo ""

echo "3. Installation de llama"
curl -LsSf https://llama.app/install.sh | sh
echo "✅ llama installé avec succès."
echo ""
echo "#####################################################################################"
echo ""

echo 4. "Installation de Brew"


/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Add linuxbrew to the list of paths usable by `sudo`
sed -Ei "s/secure_path = (.*)/secure_path = \1:\/home\/linuxbrew\/.linuxbrew\/bin/" /etc/sudoers

# Ajout du path
echo >> $HOME/.bashrc
    echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"' >> $HOME/.bashrc
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"

echo "✅ Brew installé avec succès."

# Applications à installer
APPS_BREW=(
    "smarmontools"
    "mc"
    "lm-sensors"
    "cosign"
)    
brew install "${APPS_BREW[@]}"

echo "✅ Logiciels Brew installé avec succès."
echo ""
echo "#####################################################################################"
echo ""

echo "5. Mise en place des alias"
echo "alias bh='$HOME/Git/scripts/bash-history-export.sh'" >> ~/.bashrc
echo "alias gs='$HOME/Git/scripts/git-sync.sh'" >> ~/.bashrc
# alias gemma='llama-cli --model "/cargo/local_cache/LLM/gemma-3-4b-it-Q8_0.gguf" --conversation --system-prompt "Tu es un assistant compréhensif pour la vie quotidienne : ménage, jardin, travaux, mécanique." --no-mmap --ctx-size 4096'
# alias qwen='llama-cli --model "/cargo/local_cache/LLM/Qwen2.5-Coder-3B-Instruct-abliterated-Q4_K_M.gguf" --conversation --system-prompt "Tu es un assistant concis en ingénierie des systèmes linux, scripting, développement." --no-mmap --ctx-size 4096'
# alias llama='llama-cli --model "/cargo/local_cache/LLM/Llama-3.2-3B-Instruct-Q4_K_M.gguf" --conversation --system-prompt "Tu es un assistant personnel pour aider à explorer de nouveaux concepts." --no-mmap --ctx-size 4096'
echo "✅ Alias mis en place avec succès."
echo ""
echo "#####################################################################################"
echo ""

echo 6. Installation des flatpaks
# Nota bene : on banni le mode --user pour les flatpaks. Pour une question de sécurité : installation "systeme" pour que personne (ni un utilisateur, ni un logiciel malveillant) ne puisse altérer les outils de base. En installation mode --user, un logiciel malveillant n'a besoin d'aucun privilège particulier pour alterer le contenu d'un flatpak. De plus, l'installation en mode --user n'isole pas plus les flatpaks. En mode système, il sont dans /var/lib, et donc deja en dehors des fichiers de l'OS (aucune pollution).

executer_logique() {
  flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak remote-modify --no-filter --enable flathub
  flatpak update -y


## ADAPTER LE FALLBACK OFFLINE
### Ajout de Flathub (statique, prêt à l'emploi si besoin plus tard). En mode offline, on utilise le fichier pré-téléchargé
### https://github.com/ublue-os/main/blob/main/build_files/install.sh
#mkdir -p /etc/flatpak/remotes.d/
#if [ -f /run/bin-cache/flathub.flatpakrepo ]; then
#    cp /run/bin-cache/flathub.flatpakrepo /etc/flatpak/remotes.d/flathub.flatpakrepo
#else
#    curl --retry 3 -Lo /etc/flatpak/remotes.d/flathub.flatpakrepo \
#        https://dl.flathub.org/repo/flathub.flatpakrepo
#fi

  installer_applications_communes
  if grep -qE "silverblue|kinoite|bazzite" /etc/os-release 2>/dev/null; then
    installer_applications_exclusives_atomic
  fi  
  if ! grep -qE "bazzite" /etc/os-release 2>/dev/null; then
    installer_applications_gaming_non_bazzite
  fi

  echo "Nettoyage des résidus éventuels"
  flatpak uninstall --unused

  echo "Application des permissions spécifiques"
  flatpak override --user --env=MANGOHUD=1 com.valvesoftware.Steam
  sudo flatpak override --env=MANGOHUD=1 com.valvesoftware.Steam
  # flatpak override com.usebottles.bottles --user --filesystem=xdg-data/applications
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
    "dev.deimoshall.Metamorphosis"
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
    "com.github.fabiocolacio.marker"

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
echo ""
echo "#####################################################################################"
echo ""

executer_logique "$@"
