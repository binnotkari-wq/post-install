#!/usr/bin/env bash

# NTSYNC : module kernel, gère nativement les primitives de synchronisation de
# Windows (mutex, sémaphores, événements) au niveau du système.

set -euo pipefail

echo "==> Chargement du module NTSYNC au démarrage"
backup_fichier /etc/modules-load.d/ntsync.conf sudo
echo "ntsync" | sudo tee /etc/modules-load.d/ntsync.conf
