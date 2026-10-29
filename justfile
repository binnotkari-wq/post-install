# justfile - system-settings
#
# Chaque recette appelle un script existant sans dupliquer sa logique.

set shell := ["bash", "-euo", "pipefail", "-c"]

# --- utilitaires ---

# Affiche la liste des recettes disponibles
_default:
    @{{just_executable()}} --list --list-heading $'Application des reglages systeme\n'

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
                {{just_executable()}} --show "$recipe" 2>/dev/null || echo "Aperçu indisponible"
            fi
        ' \
        --preview-window=right:50%:wrap)

    # 2. Nettoyage du nom sélectionné (enlève les espaces)
    RECIPE=$(echo "$SELECTION" | xargs)

    # 3. Exécution si ce n'est pas une ligne d'en-tête de catégorie
    if [ -n "$RECIPE" ] && ! echo "$SELECTION" | grep -q "══"; then
        {{just_executable()}} "$RECIPE"
    fi

# Confirmations d'éxecution d'une recette.
_confirm recipe:
    #!/usr/bin/env bash
    read -p "Exécuter '{{recipe}}' ? [y/N] " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        {{just_executable()}} {{recipe}}
    fi

# --- Paramétrages Ubuntu ---

# Installation outils de base
[group('Ubuntu')]
base_tools:
    ./scripts/base_tools.sh

# Suppression Snaps
[group('Ubuntu')]
delete_snaps:
    sudo ./scripts/delete_snaps.sh

# Déplacement /home et /var vers partition btrfs
[group('Ubuntu')]
migrate_home_var:
    sudo ./scripts/migrate_home_var.sh

# --- Paramétrages Fedora Atomic et dérivés ---

# Applique un karg pour la compression btrfs.
[group('Fedora Atomic')]
btrfs-kargs:
    ./scripts/btrfs-kargs.sh

# Compresse en zstd les données déployées en post-install par Bazzite (la compression n'étant pas active à ce stade)
[group('Fedora Atomic')]
existing-files_compress:
    ./scripts/existing-files_compress.sh

# Installe des logiciel par rpm ostree (logiciels demandant une integration systeme).
[group('Fedora Atomic')]
rpmostree-packages:
    ./scripts/rpmostree-packages.sh

# Correctif Plymouth/amdgpu (GPU AMD Vega intégré, ex: Picasso/Vega 8).
[group('Fedora Atomic')]
vega_plymouth-fix:
    ./scripts/vega_plymouth-fix.sh

# --- Paramétrages communs ---

# Installation de Firefox et Bazaar.
[group('Commons')]
flapak_essentials:
    ./scripts/flapak_essentials.sh

# Mise à jour des firmwares.
[group('Commons')]
firmwares-update:
    ./scripts/firmwares-update.sh

# Applique les préférences desktop Gnome.
[group('Commons')]
desktop_preferences:
    ./scripts/desktop_preferences.sh

# Installation des extensions Gnome.
[group('Commons')]
gnome-extensions:
    ./scripts/gnome-extensions.sh

# Application des alias shell.
[group('Commons')]
shell_alias:
    ./scripts/shell_alias.sh

# Mise en place des repos Github personnels (demande des credentials pour le repo privé).
[group('Commons')]
github_setup:
    ./scripts/github_setup.sh

# Limitation de l'espace disque alloué aux journaux système (100 Mo).
[group('Commons')]
log_limit:
    ./scripts/log_limit.sh

# Desactivation des services et démarrages automatiques.
[group('Commons')]
disable_startups:
    ./scripts/disable_startups.sh

# Chargement du module NTSYNC au démarrage.
[group('Commons')]
load_ntsync:
    ./scripts/load_ntsync.sh

# Paramétrage de la mémoire virtuelle.
[group('Commons')]
vm-settings:
    ./scripts/vm-settings.sh

# Paramétrage de la ZRAM.
[group('Commons')]
zram-settings:
    sudo ./scripts/zram-settings.sh

# Applique l'ensemble des réglages spécifiques aux distribution type Atomic. Opérations idempotentes.
[group('workflows')]
atomic:
    {{just_executable()}} _confirm existing-files_compress
    {{just_executable()}} _confirm btrfs-kargs
    @echo "Une connection réseau est nécessaire pour cette étape (installation de paquets)."
    {{just_executable()}} _confirm rpmostree-packages
    @echo "Appliquer uniquement lorsque l'affichage graphique de saisie LUKS est KO :"
    {{just_executable()}} _confirm vega_plymouth-fix
    @echo "Réglages appliqués. Redémarrage nécessaire ( sudo systemctl reboot )"

# Applique l'ensemble des réglages spécifiques à Ubuntu. Opérations idempotentes.
[group('workflows')]
ubuntu:
    {{just_executable()}} _confirm base_tools
    {{just_executable()}} _confirm delete_snaps
    {{just_executable()}} _confirm migrate_home_var
    @echo "Réglages appliqués. Redémarrage nécessaire ( sudo systemctl reboot )"

# Applique l'ensemble des réglages communs. Opérations idempotentes.
[group('workflows')]
commons:
    {{just_executable()}} _confirm flapak_essentials
    {{just_executable()}} _confirm firmwares-update
    {{just_executable()}} _confirm desktop_preferences
    {{just_executable()}} _confirm gnome-extensions
    {{just_executable()}} _confirm shell_alias
    {{just_executable()}} _confirm github_setup
    {{just_executable()}} _confirm log_limit
    {{just_executable()}} _confirm disable_startups
    {{just_executable()}} _confirm load_ntsync
    {{just_executable()}} _confirm vm-settings
    {{just_executable()}} _confirm zram-settings
    @echo "Réglages appliqués. Redémarrage nécessaire ( sudo systemctl reboot )"
