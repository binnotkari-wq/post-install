#!/usr/bin/env bash

set -euo pipefail

echo "==> Mise en place du repo Github. Le nom d'utilisateur et le token seront demandés par le script"

curl -sSL https://raw.githubusercontent.com/binnotkari-wq/scripts/main/git-sync.sh | bash

echo "✅ Repo Github mis en place avec succès."


