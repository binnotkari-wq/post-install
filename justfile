# justfile - system-settings
#
# Chaque recette appelle un script existant sans dupliquer sa logique.

set shell := ["bash", "-euo", "pipefail", "-c"]

# --- utilitaires ---

# Affiche la liste des recettes disponibles
_default:
    @just --list --list-heading $'Application des reglages systeme\n'

# Menu interactif groupé par catégories
_menu:
    #!/usr/bin/env bash
    
    # 1. Extraction et formatage des catégories et recettes
    # Lit le justfile, détecte les en-têtes '# ---' et les noms de recettes
    SELECTION=$(awk '
        /^# ---/ { 
            gsub(/^# --- *| *---$/, ""); 
            category=$0; 
            print "\n\033[1;35m══ " category " ══\033[0m" 
        }
        /^[a-zA-Z0-9_-]+:/ && !/^_/ { 
            split($1, a, ":"); 
            print "  " a[1] 
        }
    ' {{justfile()}} | fzf \
        --ansi \
        --layout=reverse \
        --border=rounded \
        --prompt="❯ " \
        --header="Choisis une recette par catégorie" \
        --preview '
            # Nettoie les espaces pour récuperer le nom exact de la recette
            recipe=$(echo {} | xargs);
            if [ -n "$recipe" ] && ! echo "{}" | grep -q "══"; then
                just --show "$recipe" 2>/dev/null || echo "Aperçu indisponible"
            fi
        ' \
        --preview-window=right:50%:wrap)

    # 2. Nettoyage du nom sélectionné (enlève les espaces)
    RECIPE=$(echo "$SELECTION" | xargs)

    # 3. Exécution si ce n'est pas une ligne d'en-tête de catégorie
    if [ -n "$RECIPE" ] && ! echo "$SELECTION" | grep -q "══"; then
        just "$RECIPE"
    fi

# Confirmations d'éxecution d'une recette.
_confirm recipe:
    #!/usr/bin/env bash
    read -p "Exécuter '{{recipe}}' ? [y/N] " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        just {{recipe}}
    fi

# --- Bazzite ---

# Active le logon sur le bureau au lieu de la session gamescope par défaut.
[group('Bazzite')]
bazzite_desktop-logon:
    ./scripts/bazzite_desktop-logon.sh

# --- Silverblue ---

# Installe des logiciel par rpm ostree (logiciels demandant une integration systeme).
[group('Silverblue')]
silverblue_rpmostree-packages:
    ./scripts/silverblue_rpmostree-packages.sh

# --- Radeon Vega ---

# Correctif Plymouth/amdgpu (GPU AMD Vega intégré, ex: Picasso/Vega 8).
[group('Radeon Vega')]
vega_plymouth-fix:
    ./scripts/vega_plymouth-fix.sh

# --- Toute distribution Atomic ---

# Applique un karg pour la compression btrfs.
[group('Toute distribution Atomic')]
btrfs-kargs:
    ./scripts/atomic_btrfs-kargs.sh

# Mise à jour des firmwares.
[group('Toute distribution Atomic')]
firmwares-update:
    ./scripts/firmwares-update.sh

# Limite de l'espace disque occupé par les journaux.
[group('Toute distribution Atomic')]
logs-minimize:
    ./scripts/logs-minimize.sh

# Chargement du module NTSYNC au démarrage.
[group('Toute distribution Atomic')]
load-ntsync:
    ./scripts/load-ntsync.sh

# Paramétrage de la ZRAM.
[group('Toute distribution Atomic')]
zram-setting:
    ./scripts/zram-setting.sh

# Paramétrage de la memoire virtuelle.
[group('Toute distribution Atomic')]
vm-setting:
    ./scripts/vm-setting.sh
    
# Desactivation des services et démarrages automatiques.
[group('Toute distribution Atomic')]
startup_disable:
    ./scripts/startup_disable.sh
