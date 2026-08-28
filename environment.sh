#!/bin/bash

set -ouex pipefail

# Permissions des fichiers copiés depuis system_files
chmod 644 /etc/profile.d/10-environment.sh
chmod 755 /etc/skel/Modèles/Script.sh

# activation des préférences dconf injectées
dconf update

# Ajouter les extragroups
# - user : extraGroups = [ "libvirtd" "kvm" ]; 
