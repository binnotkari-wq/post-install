#!/usr/bin/env bash

set -euo pipefail

echo "==> Installation des outils de base"

sudo apt install just git distrobox curl btrfs-compsize btrfs-progs

echo "✅ Outils de base installés avec succès."
