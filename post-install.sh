#!/usr/bin/env bash

########################
# Post installation #
########################

set -ouex pipefail

# 1. Préférences de firefox

https://raw.githubusercontent.com/binnotkari-wq/post-install/main/config/firefox/policies.json

# 2. Télécharger le repo Github

curl -sSL https://raw.githubusercontent.com/binnotkari-wq/scripts/main/git-sync.sh| bash

# 2. Mise en place des préférences Firefox



sudo mkdir -p /var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/x86_64/stable/policies
~/Git/user-deploy/config/firefox
sudo cp $HOME/Git/policies.json /var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/x86_64/stable/policies/


# 3. Installation des flatpaks
./modules/flatpaks.sh





# 4. Installation de brew

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
