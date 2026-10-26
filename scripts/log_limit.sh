#!/usr/bin/env bash

set -euo pipefail

echo "==> Limite de l'espace disque occupé par les journaux."

if sudo grep -qF 'SystemMaxUse=100M' /etc/systemd/journald.conf.d/00-limit-size.conf 2>/dev/null; then
    echo "Limitation des journaux système déjà configurée, rien à faire."
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

sudo mkdir -p /etc/systemd/journald.conf.d/
backup_fichier /etc/systemd/journald.conf.d/00-limit-size.conf sudo
echo -e "[Journal]\nSystemMaxUse=100M" | sudo tee /etc/systemd/journald.conf.d/00-limit-size.conf
sudo systemctl restart systemd-journald

echo "✅ Journaux limités avec succés."