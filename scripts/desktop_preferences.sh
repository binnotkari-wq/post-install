#!/usr/bin/env bash

set -euo pipefail

echo "==> Injection des fichiers de configuration desktop, et application des préférences."

# Sauvegarde un fichier existant en .backup avant modification.
backup_fichier () {
    local fichier="$1"
    local avec_sudo="${2:-non}"

    local backup="${fichier}.backup"

    if [[ "$avec_sudo" == "oui" ]]; then
        if sudo test -f "$fichier" && ! sudo test -f "$backup"; then
            sudo cp -a "$fichier" "$backup"
            echo "  ↳ Backup créé : ${backup}"
        fi
    else
        if [[ -f "$fichier" ]] && [[ ! -f "$backup" ]]; then
            cp -a "$fichier" "$backup"
            echo "  ↳ Backup créé : ${backup}"
        fi
    fi
}

# Copie un fichier depuis $src vers $dest, sauvegarde l'ancienne version si
# présente, applique les permissions demandées. Idempotent par nature : on peut
# relancer, le fichier est simplement re-synchronisé avec la source.
copier_fichier () {
    local dest="$1" src="$2" perms="$3" avec_sudo="${4:-non}"

    if [[ ! -f "$src" ]]; then
        echo "  ✗ Fichier source introuvable : $src" >&2
        return 1
    fi

    backup_fichier "$dest" "$avec_sudo"

    if [[ "$avec_sudo" == "oui" ]]; then
        sudo cp -f "$src" "$dest"
        sudo chmod "$perms" "$dest"
    else
        cp -f "$src" "$dest"
        chmod "$perms" "$dest"
    fi
}

sudo mkdir -p /var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/x86_64/stable/policies
sudo mkdir -p /etc/firefox/policies
sudo mkdir -p /etc/profile.d
sudo mkdir -p /etc/profile.d/local.d
sudo mkdir -p /etc/profile.d/profile
sudo mkdir -p /etc/dconf/db/local.d
sudo mkdir -p /etc/dconf/profile
mkdir -p "$HOME/Modèles"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="${SCRIPT_DIR}/../system_files"

copier_fichier "/var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/x86_64/stable/policies/policies.json" \
               "$src/etc/firefox/policies/policies.json"             644 oui
copier_fichier "/etc/firefox/policies/policies.json"      "$src/etc/firefox/policies/policies.json"      644 oui
copier_fichier "/etc/profile.d/10-environment.sh"         "$src/etc/profile.d/10-environment.sh"         644 oui
copier_fichier "/etc/dconf/db/local.d/00-defaults"        "$src/etc/dconf/db/local.d/00-defaults"        644 oui
copier_fichier "/etc/dconf/profile/user"                  "$src/etc/dconf/profile/user"                  644 oui
copier_fichier "$HOME/Modèles/Fichier Markdown.md"        "$src/etc/skel/Modèles/Fichier Markdown.md"    644 non
copier_fichier "$HOME/Modèles/Fichier texte.txt"          "$src/etc/skel/Modèles/Fichier texte.txt"      644 non
copier_fichier "$HOME/Modèles/Script.sh"                  "$src/etc/skel/Modèles/Script.sh"              755 non

# Activation des préférences dconf injectées
sudo dconf update

# Ajouter les extragroups
# - user : extraGroups = [ "libvirtd" "kvm" ];

echo "✅ Configuration desktop et préférences mises en place avec succès."