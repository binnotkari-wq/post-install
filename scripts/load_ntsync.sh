#!/usr/bin/env bash

set -euo pipefail

echo "==> Chargement du module NTSYNC au démarrage"

if lsmod | grep -q '^ntsync'; then
    echo "ntsync déjà chargé en mémoire, rien à faire."
    exit 0
fi

backup_fichier () {
    local fichier="$1"
    local besoin_sudo="${2:-}"

    local backup="${fichier}.backup"

    if [[ "$besoin_sudo" == "sudo" ]]; then
        # Ne faire le backup que si le backup n'existe pas déjà
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

backup_fichier /etc/modules-load.d/ntsync.conf sudo
echo "ntsync" | sudo tee /etc/modules-load.d/ntsync.conf

echo "✅ Chargement de ntsync au démarrage mis en place avec succès."