#!/usr/bin/env bash

#####################################################################################
# Kit de post installation, mise en place environnement. Aucune donnée personnelle. #
#####################################################################################

set -ueo pipefail   # ordre corrigé : "-oue" faisait échouer `set` (bash lisait "ue"
                     # comme argument de -o -> "ue: invalid option name")

#####################################################################################
# Fonctions utilitaires (sauvegarde + idempotence)
#####################################################################################

# Sauvegarde un fichier existant en .backup avant modification.
# Le .backup est écrasé à chaque run (pas d'historique, juste un filet de sécurité
# avant la prochaine écriture), même logique que OS_config.sh.
sauvegarder_fichier () {
    local fichier="$1" avec_sudo="${2:-non}"
    if [[ "$avec_sudo" == "oui" ]]; then
        if sudo test -f "$fichier"; then
            sudo cp -f "$fichier" "${fichier}.backup"
        fi
    else
        if [[ -f "$fichier" ]]; then
            cp -f "$fichier" "${fichier}.backup"
        fi
    fi
}

# Télécharge un fichier depuis $src vers $dest, sauvegarde l'ancienne version si
# présente, applique les permissions demandées. Idempotent par nature : on peut
# relancer, le fichier est simplement re-synchronisé avec la source.
telecharger_fichier () {
    local dest="$1" src="$2" perms="$3" avec_sudo="${4:-non}"
    sauvegarder_fichier "$dest" "$avec_sudo"
    if [[ "$avec_sudo" == "oui" ]]; then
        sudo curl -fsSL "$src" -o "$dest"
        sudo chmod "$perms" "$dest"
    else
        curl -fsSL "$src" -o "$dest"
        chmod "$perms" "$dest"
    fi
}

# Ajoute une ligne à un fichier seulement si elle n'y figure pas déjà.
# Corrige le principal problème d'idempotence du script original (alias/eval
# ajoutés en double à chaque exécution de ~/.bashrc).
ajouter_ligne_si_absente () {
    local ligne="$1" fichier="$2"
    if ! grep -qxF "$ligne" "$fichier" 2>/dev/null; then
        sauvegarder_fichier "$fichier"
        echo "$ligne" >> "$fichier"
    fi
}

executer_logique () {
mettre_en_place_preferences
mettre_en_place_alias
mettre_en_place_repo_github
}

mettre_en_place_preferences () {
echo "1. Mise en place des préférences"
sudo mkdir -p /var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/x86_64/stable/policies
sudo mkdir -p /etc/firefox/policies
sudo mkdir -p /etc/profile.d
sudo mkdir -p /etc/profile.d/local.d
sudo mkdir -p /etc/profile.d/profile
sudo mkdir -p /etc/dconf/db/local.d
sudo mkdir -p /etc/dconf/profile
mkdir -p "$HOME/Modèles"   # dossier manquant dans le script original : les curl
                            # vers $HOME/Modèles/... échouaient silencieusement (dir absent)

url="https://raw.githubusercontent.com/binnotkari-wq/post-install/main/system_files"

telecharger_fichier "/var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/x86_64/stable/policies/policies.json" "$url/etc/firefox/policies/policies.json" 644 oui
telecharger_fichier "/etc/firefox/policies/policies.json"      "$url/etc/firefox/policies/policies.json"      644 oui
telecharger_fichier "/etc/profile.d/10-environment.sh"         "$url/etc/profile.d/10-environment.sh"         644 oui
telecharger_fichier "/etc/dconf/db/local.d/00-defaults"        "$url/etc/dconf/db/local.d/00-defaults"        644 oui
telecharger_fichier "/etc/dconf/profile/user"                  "$url/etc/dconf/profile/user"                  644 oui
telecharger_fichier "$HOME/Modèles/Fichier Markdown.md"        "$url/etc/skel/Modèles/Fichier%20Markdown.md"  644 non
telecharger_fichier "$HOME/Modèles/Fichier texte.txt"          "$url/etc/skel/Modèles/Fichier%20texte.txt"    644 non
telecharger_fichier "$HOME/Modèles/Script.sh"                  "$url/etc/skel/Modèles/Script.sh"              755 non
# (le nom dupliqué "Fichier Fichier texte.txt" du script original était une coquille)

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
ajouter_ligne_si_absente "alias bh='$HOME/Git/scripts/bash-history-export.sh'" "$HOME/.bashrc"
ajouter_ligne_si_absente "alias gs='$HOME/Git/scripts/git-sync.sh'" "$HOME/.bashrc"
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
curl -sSL https://raw.githubusercontent.com/binnotkari-wq/scripts/main/git-sync.sh | bash
echo "✅ Repo Github mis en place avec succès."
echo ""
echo "#####################################################################################"
echo ""
}

installer_flatpaks() {
  echo "5. Installation des flatpaks"
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

  BASE_FLATPAKS=(
  "io.github.kolunmi.Bazaar"
  "org.gnome.TextEditor"
  "org.gnome.NautilusPreviewer"
  )
  flatpak install -y flathub "${BASE_FLATPAKS[@]}"

  APPS_EXCLUSIVES_ATOMIC=(
    # Application à installer en natif sur Nixos
    "io.github.ilya_zlobintsev.LACT"
    # "io.github.qwersyk.Newelle"
    # "org.gnome.Extensions"
  )
  if grep -qE "silverblue|kinoite|bazzite" /etc/os-release 2>/dev/null; then
  flatpak install --system -y flathub "${APPS_EXCLUSIVES_ATOMIC[@]}"
  fi

  echo "Nettoyage des résidus éventuels"
  flatpak uninstall --unused -y

  echo "✅ Flatpaks installés avec succès."
  echo ""
  echo "#####################################################################################"
  echo ""
}

executer_logique "$@"
