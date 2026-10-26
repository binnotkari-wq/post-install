#!/usr/bin/env bash

set -euo pipefail

echo "==> Paramétrage de la mémoire virtuelle."

if [[ "$(sysctl -n vm.swappiness)" == "180" ]]; then
    echo "paramètres vm déjà actifs, rien à faire."
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

 backup_fichier /etc/sysctl.d/99-vm-zram-parameters.conf sudo
cat <<'EOF' | sudo tee /etc/sysctl.d/99-vm-zram-parameters.conf
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
vm.max_map_count=1048576
EOF

echo "✅ Mémoire virtuelle paramétrée."