#!/usr/bin/env bash

#####################################################################################
# Kit de post installation, mise en place environnement. Aucune donnée personnelle. #
#####################################################################################

set -oue pipefail

executer_logique () {
mettre_en_place_preferences
mettre_en_place_alias
mettre_en_place_repo_github
installer_llama
# installer_brew                      # mettre au point la priorité sur les paquets système. Faire tests dans une vm.
installer_AIB
installer_ryzenadj
installer_flatpaks                  # pour l'instant, juste les apps de base. Le reste à intégrer avec conditions selon la distribution
masquer_autostarts_gnome
}

mettre_en_place_preferences () {
echo "1. Mise en place des préférences"
sudo mkdir -p /var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/x86_64/stable/policies
sudo mkdir -p /etc/firefox/policies
sudo mkdir -p /etc/profile.d
sudo mkdir -p /etc/profile.d/local.d
sudo mkdir -p /etc/profile.d/profile
file_url="https://raw.githubusercontent.com/binnotkari-wq/post-install/main/system_files"
sudo curl -sSL "$file_url/etc/firefox/policies/policies.json" -o 	"/var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/x86_64/stable/policies/policies.json"
sudo curl -sSL "$file_url/etc/firefox/policies/policies.json" -o	"/etc/firefox/policies/policies.json"
sudo curl -sSL "$file_url/etc/profile.d/10-environment.sh" -o		"/etc/profile.d/10-environment.sh"
sudo curl -sSL "$file_url/etc/dconf/db/local.d/00-defaults" -o		"/etc/dconf/db/local.d/00-defaults"
sudo curl -sSL "$file_url/etc/dconf/profile/user" -o			"/etc/dconf/profile/user"
curl -sSL "$file_url/etc/skel/Modèles/Fichier%20Markdown.md" -o		"$HOME/Modèles/Fichier Markdown.md"
curl -sSL "$file_url/etc/skel/Modèles/Fichier%20texte.txt" -o		"$HOME/Modèles/Fichier Fichier texte.txt"
curl -sSL "$file_url/etc/skel/Modèles/Script.sh" -o			"$HOME/Modèles/Script.sh"

# Permissions des fichiers copiés depuis system_files
sudo chmod 644 /etc/profile.d/10-environment.sh
sudo chmod 755 $HOME/Modèles/Script.sh

# activation des préférences dconf injectées
sudo dconf update

# Ajouter les extragroups
# - user : extraGroups = [ "libvirtd" "kvm" ]; 

echo "✅ Préférences mises en place avec succès."
echo ""
echo "#####################################################################################"
echo ""
}

mettre_en_place_alias () {
echo "2. Mise en place des alias"
echo "alias bh='$HOME/Git/scripts/bash-history-export.sh'" >> ~/.bashrc
echo "alias gs='$HOME/Git/scripts/git-sync.sh'" >> ~/.bashrc
# alias gemma='llama-cli --model "/cargo/local_cache/LLM/gemma-3-4b-it-Q8_0.gguf" --conversation --system-prompt "Tu es un assistant compréhensif pour la vie quotidienne : ménage, jardin, travaux, mécanique." --no-mmap --ctx-size 4096'
# alias qwen='llama-cli --model "/cargo/local_cache/LLM/Qwen2.5-Coder-3B-Instruct-abliterated-Q4_K_M.gguf" --conversation --system-prompt "Tu es un assistant concis en ingénierie des systèmes linux, scripting, développement." --no-mmap --ctx-size 4096'
# alias llama='llama-cli --model "/cargo/local_cache/LLM/Llama-3.2-3B-Instruct-Q4_K_M.gguf" --conversation --system-prompt "Tu es un assistant personnel pour aider à explorer de nouveaux concepts." --no-mmap --ctx-size 4096'
echo "✅ Alias mis en place avec succès."
echo ""
echo "#####################################################################################"
echo ""
}

mettre_en_place_repo_github () {
echo "3. Mise en place du repo Github"
curl -sSL https://raw.githubusercontent.com/binnotkari-wq/scripts/main/git-sync.sh| bash
echo "✅ Repo Github mis en place avec succès."
echo ""
echo "#####################################################################################"
echo ""
}

relocaliser_containers () {
sudo mkdir -p /var/data
sudo chown -R 1000:1000 /var/data
mkdir -p "/var/data/.local/share/containers"
ln -s -- "/var/data/.local/share/containers" "$HOME/.local/share/containers"
echo "✅ Dossier .local/share/containers relocalisé dans /var/data avec succès."
echo ""
echo "#####################################################################################"
echo ""
}

installer_llama () {
echo "4. Installation de llama"
curl -LsSf https://llama.app/install.sh | sh
echo "✅ llama installé avec succès."
echo ""
echo "#####################################################################################"
echo ""
}

installer_brew () {
echo 5. "Installation de Brew"
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Add linuxbrew to the list of paths usable by `sudo`
sudo sed -Ei "s/secure_path = (.*)/secure_path = \1:\/home\/linuxbrew\/.linuxbrew\/bin/" /etc/sudoers

# Ajout du path
echo >> $HOME/.bashrc
    echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"' >> $HOME/.bashrc
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"

echo "✅ Brew installé avec succès."

# Applications à installer
APPS_BREW=(
    "smartmontools"
    "mc"
    "lm-sensors"
    "cosign"
)    
brew install "${APPS_BREW[@]}"

brew cleanup

echo "✅ Brew (et applications brew) installé avec succès."
echo ""
echo "#####################################################################################"
echo ""
}

installer_AIB () {
echo "4. Installation de Atomic Image Builder
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/Danathar/atomic-image-builder/main/contrib/aib -o ~/.local/bin/aib
chmod +x ~/.local/bin/aib
echo "✅ atomic image builder installé avec succès."
echo ""
echo "#####################################################################################"
echo ""
}

installer_ryzenadj () {
echo "4. Installation de ryzenadj en distrobox (volontairement hors de l'OS, car provient d'un dépot tiers)"
# --- Configuration ---
BOX_NAME="ryzenadj-rootbox"
ALIAS_BOX_NAME="${BOX_NAME}"   # nom de la box utilisée dans l'alias final (adapter si différent)
SHELL_RC="${HOME}/.bashrc"

echo "==> Création de la distrobox root '${BOX_NAME}'"
distrobox-create --root "${BOX_NAME}" --image registry.fedoraproject.org/fedora-toolbox:latest --yes

echo "==> Installation de ryzenadj dans la distrobox (root)"
distrobox-enter --root -n "${BOX_NAME}" -- bash -c "
    set -euo pipefail
    sudo dnf5 -y copr enable ublue-os/bazzite
    sudo dnf5 install -y --setopt=install_weak_deps=False ryzenadj
    sudo dnf5 -y copr disable ublue-os/bazzite
"

echo "==> Export du binaire ryzenadj vers l'hôte"
distrobox-enter --root -n "${BOX_NAME}" -- distrobox-export --bin /usr/bin/ryzenadj

ALIAS_LINE_LOW="alias ryzenadj='distrobox-enter --root -n ${ALIAS_BOX_NAME} -- /usr/bin/ryzenadj --stapm-limit=15000 --fast-limit=15000 --slow-limit=15000'"
ALIAS_LINE_DEFAULT="alias ryzenadj='distrobox-enter --root -n ${ALIAS_BOX_NAME} -- /usr/bin/ryzenadj --stapm-limit=25000--fast-limit=25000 --slow-limit=25000'"

if grep -qF "alias ryzenadj=" "${SHELL_RC}" 2>/dev/null; then
    echo "==> Alias 'ryzenadj' déjà présent dans ${SHELL_RC}, remplacement"
    sed -i "\|alias ryzenadj=|d" "${SHELL_RC}"
fi

echo "==> Ajout de l'alias dans ${SHELL_RC}"
echo "${ALIAS_LINE}" >> "${SHELL_RC}"

echo "✅ ryzenadj installé avec succès."
echo ""
echo "#####################################################################################"
echo ""
}

echo 6. Installation des flatpaks
# Nota bene : on banni le mode --user pour les flatpaks. Pour une question de sécurité : installation "systeme" pour que personne (ni un utilisateur, ni un logiciel malveillant) ne puisse altérer les outils de base. En installation mode --user, un logiciel malveillant n'a besoin d'aucun privilège particulier pour alterer le contenu d'un flatpak. De plus, l'installation en mode --user n'isole pas plus les flatpaks. En mode système, il sont dans /var/lib, et donc deja en dehors des fichiers de l'OS (aucune pollution).
# Peut-être, n'installer que l'éditeur de texte et bazaar, ainsi que ce qu'on ne voit pas dans bazaar (mangohid, proton GE, boxtron...).
installer_flatpaks() {
  flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak remote-modify --no-filter --enable flathub
  flatpak update -y

  BASE_FLATPAKS=(
  "io.github.kolunmi.Bazaar"
  "org.gnome.TextEditor"
  )
  flatpak install -y flathub "${BASE_FLATPAKS[@]}"

  APPS_EXCLUSIVES_ATOMIC=(
    # Application à installer, ou déjà installée, en natif sur Nixos
    "io.github.ilya_zlobintsev.LACT"
    "io.github.qwersyk.Newelle"
    # "org.gnome.Extensions"
  )
  if grep -qE "silverblue|kinoite|bazzite" /etc/os-release 2>/dev/null; then
  flatpak install --system -y flathub "${APPS_EXCLUSIVES_ATOMIC[@]}"
  fi

  echo "Nettoyage des résidus éventuels"
  flatpak uninstall --unused
}

masquer_autostarts_gnome () {
  echo 7. Masquage des applications lancées à l'ouverture de session
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

executer_logique "$@"
