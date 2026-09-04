#!/usr/bin/env bash

set -e # Arrête le script en cas d'erreur
mkdir -p /var/tmp/logs_script_atomic
echo "🛡️ Préparation et réglages système : Fedora Atomic (Silverblue / Kinoite / Ublue )"
echo "Fedora type Atomic dispose déjà des optimisations suivantes : discard=async à travers LUKS, noatime, zstd niveau 1, zram"
echo " - aucune modification OSTREE"
echo " - correction de la lenteur, ping et deconnection du wifi (Qualcomm ath10k_pci)"
echo " - suppression des flatpaks Fedora"
echo " - optimisation BTRFS supplémentaire"
echo " - optimisation ZRAM"
echo " - allègement des services et taches de fond"
echo " - installation des logiciels en CLI"
echo "Ce script est à lancer une première fois pour la préparation et réglages système préliminaires qui provoqueront un reboot."
echo "Suite au reboot, on relance ce script. L'étape de préparation et réglages système préliminaires sera sautée pour passer aux étapes suivantes."

echo "Modifications apportées au système :"
echo " - création du fichier /etc/NetworkManager/conf.d/wifi-powersave.conf"
echo " - création du fichier /etc/fstab.bak"
echo " - modification de /etc/fstab"
echo " - modification de la ligne de commande kernel (ajout des KARGS btrfs zstd)"
echo " - création du fichier /etc/systemd/zram-generator.conf.d/zram-generator.conf"
echo " - création du fichier /etc/sysctl.d/99-zram-optimization.conf"
echo " - création du fichier /etc/systemd/journald.conf.d/00-limit-size.conf"
echo " - création du fichier $HOME/.bashrc.d/homebrew.bash"
echo " - création du dossier /home/linuxbrew/"
echo " - création du dossier $HOME/.local/bin"
echo " - création du dossier ~/.config/autostart/ et son contenu (.desktop qui annulent les lancements automatiques d'applications)"
echo "Le script est réversible, il suffit de supprimer ces éléments crées, et réactiver les services"



executer_logique() {
  echo "--- [1/3] Préparation et réglages système préliminaires ---"
  corriger_wifi
  supprimer_repo_fedora
  # updater_firmwares #provoque la fin du script, trouver une façon de poursuivre
  echo "Optimisation du niveau de compression BTRFS tenant compte du nombre de coeurs CPU"
  sauvegarder_fstab
  detecter_nb_coeurs_CPU
  adapter_fstab
  adapter_KARGS
  echo "✅ Optimisation compression BTRFS effectuée"
  optimiser_zram
  echo "✅ Optimisation ZRAM effectuée"
  redemarrer_obligatoirement_phase_1

  echo "--- [2/3] Désactivation services inutiles et compression des fichiers existants (toute nouvelle donnée sera compressée dès sa création) ---"
  compresser_fichiers_existants
  echo "✅ Compression des fichiers existants terminée."
  # updater_OS #provoque la fin du script, trouver une façon de poursuivre
  desactiver_services
  limiter_journaux
  verifier_correction_wifi
  redemarrer_obligatoirement_phase_2

  echo "--- [3/3] Installation des outils CLI (compatible toute distrib sauf Nixos qui gère les outils CLI en nixpkgs)"
  installer_brew
  prioriser_PATH_systeme
  installer_apps_CLI_brew
  preparer_local_bin
  installer_kiwix
  installer_llama_cpp_vulkan
  installer_distrobox
  echo "✅ Applications et outils installés dans /home/.homebrew et $BIN_DIR ---"
}

#===================================================
# FONCTIONS
#===================================================

# c'était quoi le problème ?
corriger_wifi() {
sudo tee /etc/NetworkManager/conf.d/wifi-powersave.conf << EOF
[connection]
wifi.powersave = 2
EOF

sudo systemctl restart NetworkManager
}

# OK dans OS config
supprimer_repo_fedora() {
  if [ ! -f /var/tmp/logs_script_atomic/1.1_supprimer_repo_fedora_OK.txt ]; then
    echo "Nettoyage des flatpaks Fedora (system-wide)"
    sudo flatpak pin --remove $(flatpak list --system --columns=ref | grep "fedoraproject") 2>/dev/null || true
    sudo flatpak uninstall -y $(flatpak list --columns=application,origin | grep -i 'fedora' | awk '{print $1}') 2>/dev/null || true
    sudo flatpak uninstall --unused
    sudo flatpak remote-delete --force fedora 2>/dev/null || true
    sudo flatpak uninstall --unused
    sudo rm -rf /var/lib/flatpak/.removed/*
    touch /var/tmp/logs_script_atomic/1.1_supprimer_repo_fedora_OK.txt
  else
    echo "Flatpaks et repo Fedora déjà supprimés et purgés"
  fi
}

# OK dans OS config
updater_firmwares() {
  sudo fwupdmgr refresh
  sudo fwupdmgr get-updates
  sudo fwupdmgr update
}

# pas utile puisqu'on n'y touche pas
sauvegarder_fstab() {
  if [ ! -f /var/tmp/logs_script_atomic/1.2_sauvegarder_fstab_OK.txt ]; then
      sudo cp /etc/fstab /etc/fstab.bak
      touch /var/tmp/logs_script_atomic/1.2_sauvegarder_fstab_OK.txt
  else
    echo "/etc/fstab déjà sauvegardé"
  fi
}

# Inutile (pseudo système "intelligent" pour choisir le mode de compression btrfs selon les capacités du CPU....bof)
detecter_nb_coeurs_CPU() {
  # Détection du CPU pour le niveau de compression
  THREADS=$(nproc)
  if [ "$THREADS" -le 4 ]; then
      LEVEL=1
  else
      LEVEL=3
  fi
}

# inutile : la seule facon de mettre en place la compression, c'est avec les KARGS, car les option de montage de / dans /etc/fstab sont ignorée du fait de OSTREE / composefs
adapter_fstab() {
  if [ ! -f /var/tmp/logs_script_atomic/1.3_adapter_fstab_OK.txt ]; then
    # Ajout de l'option de base si absente, en se basant sur la colonne 'btrfs'
    sudo sed -i '/btrfs/ { /compress=zstd/! s/\(btrfs\s\+\)\(\S\+\)/\1\2,compress=zstd/ }' /etc/fstab
    # Harmonisation du niveau de compression (zstd:1 ou zstd:3)
    sudo sed -i "s/compress=zstd\(:[0-9]\+\)\?/compress=zstd:$LEVEL/g" /etc/fstab
    touch /var/tmp/logs_script_atomic/1.3_adapter_fstab_OK.txt
    echo "✅ Configuration Btrfs réglée sur zstd:$LEVEL (CPU $THREADS threads)."
  else
    echo "/etc/fstab déjà adapté"
  fi
}

# OK dans OS config
adapter_KARGS() {
  if [ ! -f /var/tmp/logs_script_atomic/1.4_adapter_KARGS_OK.txt ]; then
    # On vérifie si compress-force est déjà présent pour éviter les doublons
    if ! rpm-ostree kargs | grep -q "compress-force"; then
        sudo rpm-ostree kargs --delete="rootflags=subvol=root" --append="rootflags=subvol=root,compress-force=zstd:$LEVEL"
    fi
    touch /var/tmp/logs_script_atomic/1.4_adapter_KARGS_OK.txt
  else
    echo "KARGS déjà adaptés"
  fi
}

# OK dans OS config
optimiser_zram() {
  if [ ! -f /var/tmp/logs_script_atomic/1.5_optimiser_zram_OK.txt ]; then
    # 1. Détection de la RAM totale en Go
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_GB=$(( (TOTAL_RAM_KB + 1024 * 1024 - 1) / (1024 * 1024) ))

    echo "--- Détection du système ---"
    echo "RAM détectée : ${TOTAL_RAM_GB} Go"

    # 2. Définition des variables selon la RAM
    # Valeurs par défaut (Sécuritaires)
    ZRAM_RATIO="1"
    SWAPPINESS="150"

    if [ "$TOTAL_RAM_GB" -le 8 ]; then
        echo "Configuration : Profil Basse RAM (Optimisation agressive)"
        ZRAM_RATIO="1.5"
        SWAPPINESS="180"
    elif [ "$TOTAL_RAM_GB" -le 12 ]; then
        echo "Configuration : Profil RAM Moyenne"
        ZRAM_RATIO="1.2"
        SWAPPINESS="160"
    else
        echo "Configuration : Profil Gaming / Haute RAM (Performance brute)"
        ZRAM_RATIO="1"
        SWAPPINESS="150"
    fi

    # 3. Création de la configuration ZRAM
    echo "--- Configuration de zram-generator ---"
    sudo mkdir -p /etc/systemd/zram-generator.conf.d
cat <<EOF | sudo tee /etc/systemd/zram-generator.conf.d/zram-generator.conf
[zram0]
zram-size = ram * $ZRAM_RATIO
compression-algorithm = zstd
swap-priority = 100
EOF

    # 4. Application de la "Sauce Secrète" dans sysctl
    echo "--- Configuration de la 'Sauce Secrète' (sysctl) ---"
    # On crée un fichier dédié dans /etc/sysctl.d/ pour ne pas polluer le sysctl.conf principal
cat <<EOF | sudo tee /etc/sysctl.d/99-zram-optimization.conf
vm.page-cluster = 0
vm.swappiness = $SWAPPINESS
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
EOF

    # 5. Application immédiate
    echo "--- Application des paramètres ---"
    sudo sysctl --system
    touch /var/tmp/logs_script_atomic/1.5_optimiser_zram_OK.txt
    echo "Note : Pour que le changement de taille ZRAM soit effectif, un redémarrage est conseillé."
    echo "Terminé !"
  else
    echo "ZRAM déjà optimisée"
  fi
}

redemarrer_obligatoirement_phase_1() {
  if [ ! -f /var/tmp/logs_script_atomic/1.6_reboot_OK.txt ]; then
    local r=""  # On l'initialise à vide pour satisfaire set -u
    local message="${1:-Redémarrage requis}"
    until [ "$r" = "oui" ]; do 
        read -rp "$message (oui) : " r
    done
    echo "Initialisation du redémarrage..."
    touch /var/tmp/logs_script_atomic/1.6_reboot_OK.txt
    sudo systemctl reboot
  else
    echo "Redémarrage phase 1 déjà effectué"
  fi
}

compresser_fichiers_existants() {
  if [ ! -f /var/tmp/logs_script_atomic/2.1_compresser_fichiers_existants_OK.txt ]; then
    sudo btrfs filesystem defragment -r -v -czstd /var &&
    sudo btrfs filesystem defragment -r -v -czstd /var/home &&
    touch /var/tmp/logs_script_atomic/2.1_compresser_fichiers_existants_OK.txt
  else
    echo "Fichiers existants déjà compressés"
  fi
}

desactiver_services() {
  if [ ! -f /var/tmp/logs_script_atomic/2.2_desactiver_services_OK.txt ]; then
    # --- SECTION REVERSER ---
    # Pour réactiver un service si besoin (ex: impression ou gnome-software) :
    # systemctl --user unmask gnome-software.service
    # systemctl --user start gnome-software.service
    sudo systemctl disable --now \
    virtqemud.service \ # bazzite
    virtlxcd.service \ # bazzite
    virtvboxd.service \ # bazzite
    NetworkManager-wait-online.service \ # bazzite
    geoclue.service \
    ModemManager.service \
    avahi-daemon.service \
    sssd-kcm.service gssproxy.service \
    cups.service \
    pcscd.service
    systemctl --user mask --now \
    evolution-addressbook-factory.service \
    evolution-calendar-factory.service \
    evolution-alarm-notify.service \
    evolution-source-registry.service \
    org.gnome.SettingsDaemon.PrintNotifications.service \
    org.gnome.SettingsDaemon.Smartcard.service \
    org.gnome.SettingsDaemon.Wwan.service \
    # gnome-software.service # laisser activé, car c'est finalement un des composants principaux de la philosophie Fedora Atomic.
    touch /var/tmp/logs_script_atomic/2.2_desactiver_services_OK.txt
  else
    echo "Services déjà désactivés"
  fi
}

desactiver_autostarts() {
  # Bazzite lance des apps au démarrage de la session de bureau. On annule ces lancements.
  # Créer le dossier autostart local s'il n'existe pas
  mkdir -p ~/.config/autostart

  # Liste des services à désactiver
  services=(
    "steam.desktop"
    "vboxclient.desktop"
    "vmware-user.desktop"
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
}

limiter_journaux() {
  if [ ! -f /var/tmp/logs_script_atomic/2.3_limiter_journaux_OK.txt ]; then
    sudo mkdir -p /etc/systemd/journald.conf.d/
    echo -e "[Journal]\nSystemMaxUse=100M" | sudo tee /etc/systemd/journald.conf.d/00-limit-size.conf
    sudo systemctl restart systemd-journald
    touch /var/tmp/logs_script_atomic/2.3_limiter_journaux_OK.txt
  else
    echo "Journalisation déjà limitée"
  fi
}

updater_OS() {
  sudo rpm-ostree status
  sudo rpm-ostree upgrade --check
  sudo rpm-ostree upgrade
}

verifier_correction_wifi() {
echo "Vérification de la desactivation du powersave wifi :"
iw dev wlp2s0 get power_save
}

redemarrer_obligatoirement_phase_2() {
  if [ ! -f /var/tmp/logs_script_atomic/2.4_reboot_OK.txt ]; then
    local r=""  # On l'initialise à vide pour satisfaire set -u
    local message="${1:-Redémarrage requis}"
    until [ "$r" = "oui" ]; do 
        read -rp "$message (oui) : " r
    done
    echo "Initialisation du redémarrage..."
    touch /var/tmp/logs_script_atomic/2.4_reboot_OK.txt
    sudo systemctl reboot
  else
    echo "Redémarrage phase 2 déjà effectué"
  fi
}

installer_brew() {
  if [ ! -f /var/tmp/logs_script_atomic/3.2_installer_brew_OK.txt ]; then
    # Téléchargement et installation de Brew. Brew permet d'installer des logiciels CLI en espace utilisateur.
    # Brew sera installé dans /home/linuxbrew/.linuxbrew/. Le script s'occupe de régler les permissions.
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    sleep 5
    touch /var/tmp/logs_script_atomic/3.2_installer_brew_OK.txt
  else
    echo "Brew déjà installé"
  fi
}

prioriser_PATH_systeme() {
  if [ ! -f /var/tmp/logs_script_atomic/3.3_prioriser_PATH_systeme_OK.txt ]; then
    mkdir -p "$HOME/.bashrc.d"
    # On crée (ou écrase) le fichier dédié à Brew sans toucher au .bashrc de Stow
cat << 'EOF' > "$HOME/.bashrc.d/homebrew.bash"
# Configuration Homebrew (Spécifique Fedora Atomic)
if [ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
    # Initialisation de l'environnement Brew
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"

    # Sécurité : on place Brew en fin de PATH pour ne pas écraser l'OS
    export PATH="$PATH:/home/linuxbrew/.linuxbrew/bin"

    # On garantit que les binaires système restent prioritaires
    export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
fi
EOF

    # Application immédiate pour la session actuelle
    source "$HOME/.bashrc.d/homebrew.bash"
    echo "Configuration Brew isolée dans ~/.bashrc.d/homebrew.bash"
    touch /var/tmp/logs_script_atomic/3.3_prioriser_PATH_systeme_OK.txt
  else
    echo "PATH déjà priorisés sur systeme"
  fi
}

installer_apps_CLI_brew() {
  # Applications CLI à installer :
  # (ne pas installer distrobox via brew, car cela va installer également une version brew de podman, alors que celui-ci est
  # installé nativement sur les Fedora Atomic (Silverblue, Bazzite ...). Distrobox sera donc installé en binaire natif standalone
  # (voir plus bas). Powertop n'est pas disponibles dans Brew
  APPS_CLI=(
    "gcc"
    "mc"
    "lm-sensors"
    "zellij"
    "btop"
    "htop"
    "stow"
    "duf"
    "mdcat"
    "stress-ng"
    "just"
    "go"
    "dialog"
    "pandoc"
    "shellcheck"
    "7zip"
  )
  brew install "${APPS_CLI[@]}"
  touch /var/tmp/logs_script_atomic/3.4_installer_apps_CLI_brew_OK.txt
}

preparer_local_bin() {
  if [ ! -f /var/tmp/logs_script_atomic/3.1_preparer_local_bin_OK.txt ]; then
    # 2. Mise en place des binaires standalone qui ne sont pas disponibles dans brew
    BIN_DIR="$HOME/.local/bin"
    mkdir -p "$BIN_DIR"
    echo "📥 ...binaires standalone (dans $BIN_DIR)..."
    touch /var/tmp/logs_script_atomic/3.1_preparer_local_bin_OK.txt 
  else
    echo "$HOME/.local/bin déjà préparé"
  fi
}

installer_kiwix() {
  echo "  -> Récupération de Kiwix Tools..."
  curl -L "https://download.kiwix.org/release/kiwix-tools/kiwix-tools_linux-x86_64.tar.gz" | tar -xz -C "$BIN_DIR" --strip-components=1
  touch /var/tmp/logs_script_atomic/3.5_installer_kiwix_OK.txt
}

installer_llama_cpp_vulkan() {
  LLAMA_DIR="$HOME/.local/lib/llama-cpp"
  mkdir -p "$LLAMA_DIR"
  echo "  -> Installation de llama.cpp Vulkan..."
  # Téléchargement et extraction propre
  curl -L "https://github.com/ggml-org/llama.cpp/releases/download/b8012/llama-b8012-bin-ubuntu-vulkan-x64.tar.gz" | tar -xz -C "$LLAMA_DIR" --strip-components=1

  # Création du wrapper dans ~/.local/bin
  cat <<EOF > "$BIN_DIR/llama-server"
#!/usr/bin/env bash
export LD_LIBRARY_PATH="$LLAMA_DIR:\$LD_LIBRARY_PATH"
exec "$LLAMA_DIR/llama-server" "\$@"
EOF
  chmod +x "$BIN_DIR/llama-server"
  touch /var/tmp/logs_script_atomic/3.6_installer_llama_cpp_vulkan_OK.txt
}

installer_distrobox() {
  echo "  -> Installation de distrobox..."
  # le script officiel installe correctement l'ensemble des fichiers dans .local
  curl -s https://raw.githubusercontent.com/89luca89/distrobox/main/install | sh -s -- --prefix ~/.local
  touch /var/tmp/logs_script_atomic/3.7_installer_distrobox_OK.txt
}

# =============================================================================
# EXECUTION
# =============================================================================

executer_logique "$@"
