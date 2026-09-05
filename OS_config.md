# Script de post-installation Fedora Silverblue — `OS_config.sh`

## Sommaire

- [1. Pourquoi ce script existe](#1-pourquoi-ce-script-existe)
- [2. Principes de conception](#2-principes-de-conception)
  - [2.1. Idempotence](#21-idempotence)
  - [2.2. Sauvegarde avant modification (schéma A/B)](#22-sauvegarde-avant-modification-schéma-ab)
  - [2.3. Résilience aux échecs (`set -e` et cas particuliers)](#23-résilience-aux-échecs-set--e-et-cas-particuliers)
- [3. Neutralisation des mises à jour automatiques](#3-neutralisation-des-mises-à-jour-automatiques)
- [4. Détail des étapes](#4-détail-des-étapes)
  - [4.1. Mise à jour des firmwares](#41-mise-à-jour-des-firmwares)
  - [4.2. Limitation des journaux systemd](#42-limitation-des-journaux-systemd)
  - [4.3. Suppression des Flatpaks Fedora](#43-suppression-des-flatpaks-fedora)
  - [4.4. Compression BTRFS via karg](#44-compression-btrfs-via-karg)
  - [4.5. Module noyau NTSYNC](#45-module-noyau-ntsync)
  - [4.6. Paramétrage de la ZRAM](#46-paramétrage-de-la-zram)
  - [4.7. Paramétrage de la mémoire virtuelle](#47-paramétrage-de-la-mémoire-virtuelle)
  - [4.8. Désactivation de services et masquage d'autostarts](#48-désactivation-de-services-et-masquage-dautostarts)
  - [4.9. Installation de paquets système (layering rpm-ostree)](#49-installation-de-paquets-système-layering-rpm-ostree)
  - [4.10. Redémarrage final](#410-redémarrage-final)
- [5. Fonctions utilitaires transverses](#5-fonctions-utilitaires-transverses)
- [6. Limites connues et compromis assumés](#6-limites-connues-et-compromis-assumés)
- [7. Utilisation](#7-utilisation)

---

## 1. Pourquoi ce script existe

Ce script configure un système **Fedora Silverblue fraîchement installé**, dans une logique bien précise : personnaliser le système sans jamais s'écarter de la base garantie par Fedora.

L'alternative aurait été de construire une **image bootc custom** (rebuild complet de l'image système via un Containerfile, cf. le projet parallèle `fedora_custom-bootc`). Cette approche offre plus de contrôle, mais génère une charge de maintenance permanente : suivre les mises à jour Fedora en amont, déboguer les régressions liées au pipeline de build (dracut, initramfs, Plymouth, SELinux, CI...), et assumer la responsabilité d'une image qui n'est plus "celle de Fedora".

**Ce script prend le parti inverse** : partir de l'image Silverblue officielle, non modifiée, et appliquer les personnalisations *après coup*, via des mécanismes standards et supportés (kargs, layering rpm-ostree, fichiers de configuration sous `/etc/`). On garde :

- La garantie de mise à jour et de support de Fedora, sans divergence de build.
- La possibilité de revenir en arrière facilement (rollback rpm-ostree natif, backups des fichiers modifiés).
- Une charge mentale de maintenance minimale : pas de pipeline CI à surveiller, pas de build à déboguer.

En échange, on renonce à certaines optimisations profondes qu'une image custom permettrait (ex : suppression de paquets à la compilation plutôt qu'a posteriori). C'est un compromis assumé : ce script vise le **système immuable mais personnalisé "as intended"**, pas le système sur-mesure à la Bazzite/UBlue.

## 2. Principes de conception

Trois principes structurent l'ensemble du script, discutés et affinés au fil de son développement.

### 2.1. Idempotence

Le script doit pouvoir être relancé plusieurs fois sans dommage ni comportement différent. En pratique, cette propriété est obtenue de deux façons distinctes selon les étapes :

- **Par écrasement plutôt qu'accumulation** : toutes les écritures de fichiers de configuration utilisent une redirection qui **remplace** le contenu (`tee`, `>`), jamais une redirection qui **ajoute** (`>>`). Relancer le script réécrit le même contenu, sans dupliquer de lignes.
- **Par tolérance native de l'outil appelé** : `systemctl disable`/`mask` sur une unité déjà désactivée/masquée ne provoque pas d'erreur bloquante ; `flatpak uninstall --unused` ne fait rien s'il n'y a rien à faire ; `mkdir -p` ne râle jamais si le dossier existe déjà.
- **Par vérification explicite, quand ni l'un ni l'autre ne suffit** : deux fonctions ont besoin d'une garde explicite, car l'opération sous-jacente n'est pas naturellement idempotente ou serait coûteuse à répéter inutilement.

Exemple dans `injecter_KARGS_compression_btrfs` :

```bash
if ! rpm-ostree kargs | grep -q 'compress=zstd:1'; then
    sudo rpm-ostree cancel 2>/dev/null || true
    sudo rpm-ostree kargs --delete="rootflags=subvol=root" --append="rootflags=subvol=root,compress=zstd:1"
    REBOOT_NEEDED=1
    echo "✅ Compression BTRFS mise en place avec succès."
else
    echo "✅ Compression BTRFS déjà en place."
fi
```

Et dans `installer_paquets_systeme`, où l'on ne construit la liste des paquets à installer qu'à partir de ceux qui manquent réellement :

```bash
for pkg in "${NEEDED_PKGS[@]}"; do
    if ! rpm -q --quiet "$pkg"; then
        TO_INSTALL+=("$pkg")
    else
        echo "  - $pkg déjà installé, skip"
    fi
done
```

### 2.2. Sauvegarde avant modification (schéma A/B)

Chaque fichier créé ou modifié par le script (à l'exception de la suppression des Flatpaks Fedora, qui n'est pas une opération de fichier) est sauvegardé **avant** d'être écrasé, via la fonction `backup_fichier`.

Le choix de conception ici est délibérément **minimaliste** : un seul fichier `.backup` par fichier concerné, écrasé à chaque exécution du script — pas d'historique horodaté. Le raisonnement suit directement le fonctionnement des distributions Linux immuables elles-mêmes (dont Fedora Silverblue) : un rootfs "courant" et un rootfs "précédent" garanti fonctionnel, jamais une pile d'historique à gérer.

```bash
# Sauvegarde un fichier existant en fichier.ext.backup avant modification (schéma A/B, à l'image
# des rootfs A/B des distributions atomiques : une version courante, une version précédente
# garantie fonctionnelle). Le backup est écrasé à chaque exécution : il ne conserve donc que
# l'état d'AVANT le dernier run, pas un historique. Ne fait rien si le fichier n'existe pas
# encore (rien à sauvegarder).
backup_fichier () {
  local fichier="$1"
  local besoin_sudo="${2:-}"

  if [[ "$besoin_sudo" == "sudo" ]]; then
    if sudo test -f "$fichier"; then
      sudo cp -a "$fichier" "${fichier}.backup"
      echo "  ↳ Backup créé : ${fichier}.backup"
    fi
  else
    if [[ -f "$fichier" ]]; then
      cp -a "$fichier" "${fichier}.backup"
      echo "  ↳ Backup créé : ${fichier}.backup"
    fi
  fi
}
```

Le second paramètre (`sudo`) distingue les fichiers appartenant à root (sous `/etc/`, `/usr/`) des fichiers utilisateur (sous `~/.config/`), qui n'ont pas besoin d'élévation de droits pour être lus ou copiés.

### 2.3. Résilience aux échecs (`set -e` et cas particuliers)

Le script tourne sous `set -oue pipefail`, donc toute commande retournant un code de sortie non-nul interrompt immédiatement l'exécution. Ce choix est volontaire (on ne veut pas continuer aveuglément après un échec réel), mais il a révélé plusieurs outils dont le code de sortie non-nul ne signifie *pas* un échec :

- **`fwupdmgr`** retourne un code non-nul dès qu'il n'y a rien à mettre à jour — comportement documenté, pas une erreur.
- **`systemctl disable`/`mask`** sur une liste d'unités échoue *entièrement* (pas seulement pour l'unité fautive) si une seule unité de la liste n'existe pas sur le système cible. Or la liste de ce script mélange volontairement des unités génériques et des unités spécifiques à certaines variantes (Bazzite notamment), pour que le même script serve sur plusieurs types d'installations.

Dans les deux cas, le correctif est un `|| true` **ciblé** — jamais un `set +e` global, qui masquerait aussi les vraies erreurs :

```bash
# fwupdmgr retourne un code de sortie non-nul dès qu'il n'y a rien à faire
# (pas de mise à jour disponible) : comportement normal, pas une erreur.
sudo fwupdmgr refresh || true
sudo fwupdmgr get-updates || true
sudo fwupdmgr update || true
```

```bash
# Note : cette liste mélange des unités génériques et des unités spécifiques à certaines
# variantes (ex. Bazzite). Sur une cible où une unité n'existe pas, systemctl retourne un
# code non-nul pour TOUTE la commande (pas seulement l'unité concernée) : le || true évite
# que set -e n'interrompe le script, sans empêcher la désactivation des unités qui existent.
sudo systemctl disable \
  NetworkManager-wait-online.service \
  ...
  pcscd.service || true
```

## 3. Neutralisation des mises à jour automatiques

C'est le point le plus délicat du script, découvert par un échec reproductible en test : sur une installation Silverblue **fraîche**, une mise à jour automatique se déclenche en tâche de fond peu après le boot. Si le script tente une opération rpm-ostree (`kargs`, `install`) pendant que cette mise à jour est en cours, rpm-ostree refuse (une seule transaction à la fois) :

```
error: Transaction in progress: upgrade
```

Deux mécanismes indépendants peuvent déclencher cette mise à jour automatique :

1. **`rpm-ostreed-automatic.timer`** : le timer systemd qui vérifie et met en scène ("stage") les mises à jour peu après le boot.
2. **GNOME Software**, qui effectue sa *propre* vérification en arrière-plan via D-Bus, depuis la session graphique — indépendamment du timer ci-dessus.

Couper uniquement le premier ne suffit pas : c'est précisément ce qui a été observé en test (le script échouait toujours sur `installer_paquets_systeme`, plusieurs minutes après avoir coupé le timer, une fois que GNOME Software avait relancé une transaction de son côté).

**Enjeu de fond, au-delà de l'erreur immédiate** : au-delà du blocage, laisser une mise à jour automatique s'exécuter *pendant* le script pose un problème plus sournois — elle pourrait écrire des données sur le disque **avant** que la compression BTRFS ne soit activée par `injecter_KARGS_compression_btrfs`, ce qui irait à l'encontre de l'objectif recherché (voir [4.4](#44-compression-btrfs-via-karg)). D'où le choix délibéré de **couper toute mise à jour automatique pour la durée du script**, plutôt que d'attendre qu'une transaction en cours se termine.

```bash
arreter_maj_automatiques () {
  echo "==> Arrêt des mises à jour automatiques rpm-ostree pour la durée du script"
  sudo rpm-ostree cancel 2>/dev/null || true
  sudo systemctl stop rpm-ostreed-automatic.timer rpm-ostreed-automatic.service 2>/dev/null || true
  sudo systemctl disable rpm-ostreed-automatic.timer 2>/dev/null || true
  gsettings set org.gnome.software download-updates false 2>/dev/null || true
  gsettings set org.gnome.software download-updates-notify false 2>/dev/null || true
  pkill -x gnome-software 2>/dev/null || true
  trap reactiver_maj_automatiques EXIT
  echo "✅ Mises à jour automatiques stoppées le temps du script."
  ...
}
```

En complément (et non en remplacement — un `cancel` immédiat, pas une boucle d'attente), un second `rpm-ostree cancel` défensif est placé juste avant chaque opération rpm-ostree mutante du script (`kargs`, `install`), pour parer une transaction qui aurait pu être relancée dans l'intervalle :

```bash
sudo rpm-ostree cancel 2>/dev/null || true
sudo rpm-ostree kargs --delete="rootflags=subvol=root" --append="rootflags=subvol=root,compress=zstd:1"
```

**Réactivation garantie via `trap EXIT`** : couper `rpm-ostreed-automatic.timer` change durablement l'état du système (contrairement à un simple arrêt temporaire, `systemctl disable` retire le lien d'activation au démarrage). Il est donc impératif que le système ne reste jamais dans cet état si le script échoue en cours de route. La réactivation n'est donc pas appelée explicitement en fin de script, mais posée comme un `trap` juste après l'arrêt initial :

```bash
trap reactiver_maj_automatiques EXIT
```

Ce trap se déclenche **quel que soit le chemin de sortie du script** : succès normal, erreur remontée par `set -e` à n'importe quelle étape ultérieure, ou interruption manuelle (Ctrl+C). Le système ne peut donc jamais rester avec les mises à jour automatiques désactivées suite à un échec.

## 4. Détail des étapes

L'ordre d'exécution est fixé dans `executer_logique`, la fonction orchestratrice :

```bash
executer_logique () {
  arreter_maj_automatiques
  mettre_a_jour_firmwares
  limiter_journaux
  supprimer_flatpak_fedora
  injecter_KARGS_compression_btrfs
  charger_module_ntsync
  parametrer_zram
  parametrer_memoire_virtuelle
  desactiver_service
  masquer_autostarts_gnome
  installer_paquets_systeme
  redemarrer
}
```

### 4.1. Mise à jour des firmwares

Appelle `fwupdmgr` (refresh, get-updates, update) pour s'assurer que le firmware matériel (BIOS/UEFI, contrôleurs, etc.) est à jour dès le départ. Voir [2.3](#23-résilience-aux-échecs-set--e-et-cas-particuliers) pour la gestion de son code de sortie particulier.

### 4.2. Limitation des journaux systemd

Par défaut, `systemd-journald` peut consommer une part significative de l'espace disque au fil du temps. Le script plafonne cette taille à 100 Mo :

```bash
echo -e "[Journal]\nSystemMaxUse=100M" | sudo tee /etc/systemd/journald.conf.d/00-limit-size.conf
sudo systemctl restart systemd-journald
```

### 4.3. Suppression des Flatpaks Fedora

Fedora Silverblue installe par défaut des Flatpaks provenant du remote `fedoraproject` (ex : LibreOffice packagé par Fedora). Ce script les retire pour privilégier une installation exclusivement via Flathub par la suite (stratégie documentée dans le projet `fedora_custom-bootc` : pas de Flatpaks embarqués, gestion via un dépôt USB dédié pour l'installation hors-ligne d'applications Flathub).

Point technique notable : la liste des refs/apps à traiter peut contenir plusieurs éléments (plusieurs lignes), il faut donc les faire passer en arguments **distincts** aux commandes `flatpak`, sans les fusionner en une seule chaîne. La solution retenue passe par des tableaux bash (`mapfile`), qui satisfont aussi shellcheck (SC2046) :

```bash
mapfile -t REFS_FEDORA < <(flatpak list --system --columns=ref | grep "fedoraproject")
if ((${#REFS_FEDORA[@]})); then
  sudo flatpak pin --remove "${REFS_FEDORA[@]}" 2>/dev/null || true
fi
```

C'est la seule étape de création/modification de fichier explicitement **exclue** du mécanisme de backup (décision explicite : cette étape ne modifie pas un fichier de configuration mais un état d'installation Flatpak).

### 4.4. Compression BTRFS via karg

**Choix technique : `compress=zstd:1`** (niveau de compression zstd le plus bas).

La justification tient à une limitation connue de composefs (le mécanisme d'image immuable sous-jacent à Fedora Atomic/bootc) : il ne respecte pas l'intégralité de `/etc/fstab`, ce qui empêche de configurer la compression BTRFS par la voie standard (options de montage dans fstab). Le contournement consiste à injecter l'option de compression directement comme paramètre du noyau (karg) :

```bash
sudo rpm-ostree kargs --delete="rootflags=subvol=root" --append="rootflags=subvol=root,compress=zstd:1"
```

Référence du problème amont : [gitlab.com/fedora/ostree/sig — work item #72](https://gitlab.com/fedora/ostree/sig/-/work_items/72).

Le niveau `zstd:1` (plutôt qu'un niveau de compression plus agressif comme `zstd:3`) n'est pas un choix arbitraire ni une simple intuition de compromis CPU/gain d'espace : il résulte d'un **test comparatif mené spécifiquement pour trancher la question** (conversation dédiée : *"comparaison des options de compression btrfs zstd"*), via un script de benchmark comparant plusieurs options (`compress=zstd:1`, `compress=zstd:3`, `compress-force=zstd:1`, `compress-force=zstd:3`) sur des copies répétées d'un même échantillon de fichiers.

Point méthodologique notable de ce test : une première série de mesures montrait un écart net et systématique (~4s) en défaveur de `zstd:1`, contre-intuitif puisque `zstd:1` est censé demander moins d'effort de compression donc être plus rapide. L'investigation a révélé un **effet d'ordre** : le script de test exécutait toujours `compress=zstd:1` en premier, sur une image dont les chunks disque n'étaient pas encore alloués — le biais venait du protocole de test, pas de l'option de compression elle-même. Après randomisation de l'ordre des tests et ajout d'un run d'échauffement, le biais a disparu : sur 6 comparaisons directes zstd:1 vs zstd:3, zstd:1 s'est montré plus rapide ou égal dans 5 cas sur 6 (écarts de 0.5 à 1.9s sur des copies de 8-12s), conforme à la théorie une fois le bruit de mesure maîtrisé.

**Conclusion retenue** : l'écart de vitesse/ratio entre `zstd:1` et `zstd:3` est trop faible pour constituer un critère de choix déterminant sur l'usage visé (rootfs, dotfiles, configuration). `zstd:1` a été retenu comme choix raisonnable et simple, en particulier pour les machines les moins puissantes du parc (X240, L380) — `zstd:3` aurait été un choix tout aussi défendable.

C'est l'étape qui a motivé, en creux, tout le travail de neutralisation des mises à jour automatiques décrit en [section 3](#3-neutralisation-des-mises-à-jour-automatiques) : il est important que ce karg soit posé **avant** toute écriture disque significative, pour que la compression s'applique aussi largement que possible dès le début de la vie du système.

### 4.5. Module noyau NTSYNC

`ntsync` est un module noyau qui améliore les performances de synchronisation pour les applications Windows exécutées via Wine/Proton — pertinent ici en prévision d'un usage gaming (le PC gaming du parc de Benoit tourne actuellement sous Bazzite/Proton).

```bash
echo "ntsync" | sudo tee /etc/modules-load.d/ntsync.conf
```

**Point d'attention retenu** : le fichier doit être écrit sous `/etc/modules-load.d/`, et non `/usr/lib/modules-load.d/` — ce second chemin fait partie de l'arbre ostree en lecture seule sur une image atomique, toute tentative d'écriture y échoue.

### 4.6. Paramétrage de la ZRAM

Configure un périphérique de swap compressé en RAM :

```
[zram0]
zram-size = ram * 1.5
compression-algorithm = zstd
swap-priority = 100
```

Ces valeurs (taille et priorité) reprennent la configuration présentée dans le billet ["My Opinionated Fedora Silverblue Setup"](https://dev.to/archerallstars/my-opinionated-fedora-silverblue-setup-4o9p) (Archer Allstars), qui juge la configuration ZRAM par défaut de Fedora trop conservatrice, en particulier sur un système peu doté en RAM.

- `zram-size = ram * 1.5` : la zone de swap compressée fait une fois et demie la RAM physique — un choix généreux qui exploite le fait que les données y sont compressées (le ratio réel de swap disponible est donc supérieur au multiplicateur affiché).
- `swap-priority = 100` : priorité maximale, pour que le noyau utilise systématiquement la ZRAM avant tout autre espace de swap disponible. La justification de la source : la ZRAM ne repose pas sur un disque lent, donc autant compresser les données en RAM le plus tôt possible plutôt que d'attendre que le système soit déjà à court de ressources pour le faire.

### 4.7. Paramétrage de la mémoire virtuelle

Ajuste plusieurs paramètres `sysctl` pour un système qui repose principalement sur la ZRAM comme espace de swap :

```
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
vm.max_map_count=1048576
```

Les quatre premiers paramètres proviennent, comme la configuration ZRAM ci-dessus, du billet [Archer Allstars](https://dev.to/archerallstars/my-opinionated-fedora-silverblue-setup-4o9p), qui les qualifie lui-même de "secret sauce" — un ensemble de réglages emprunté à un **effort d'optimisation porté par Pop!\_OS** pour améliorer la réactivité du système sous pression mémoire, spécifiquement pensé pour les postes de bureau utilisant un swap compressé en RAM : [github.com/pop-os/default-settings/pull/163](https://github.com/pop-os/default-settings/pull/163). Ils recoupent par ailleurs les recommandations générales du wiki Arch Linux sur l'optimisation du swap ZRAM : [wiki.archlinux.org/title/Zram#Optimizing_swap_on_zram](https://wiki.archlinux.org/title/Zram#Optimizing_swap_on_zram).

- **`vm.swappiness = 180`** : valeur volontairement bien au-delà de l'échelle historique 0-100 (le noyau moderne l'autorise) — pousse le système à swapper de façon plus agressive vers la ZRAM, cohérent avec le fait que ce swap est rapide (en RAM, compressé) plutôt que sur disque, contrairement à l'hypothèse implicite de l'échelle traditionnelle.
- **`vm.watermark_boost_factor = 0`** et **`vm.watermark_scale_factor = 125`** : réduisent l'agressivité de la réclamation de mémoire proactive du noyau, pensés pour la combinaison ZRAM (évite des pics de compression/décompression inutiles déclenchés trop tôt).
- **`vm.page-cluster = 0`** : désactive le regroupement de pages en lecture pour le swap — pertinent spécifiquement pour la ZRAM, où lire une page à la fois est plus efficace que lire par lots (contrairement à un swap sur disque rotatif, où grouper les lectures a un sens).

Le cinquième paramètre a une origine distincte, propre à Fedora :

- **`vm.max_map_count = 1048576`** : augmente la limite de mappings mémoire par processus. Reprend la valeur portée par la proposition officielle Fedora ["Increase vm.max_map_count"](https://fedoraproject.org/wiki/Changes/IncreaseVmMaxMapCount), motivée notamment par les besoins de jeux modernes (via Proton/Steam) et de certaines applications (bases de données, JVM) qui peuvent dépasser la valeur par défaut du noyau.

### 4.8. Désactivation de services et masquage d'autostarts

Deux volets distincts :

**a) Services systemd** (`desactiver_service`) : désactivation (`disable`) et masquage (`mask`) d'un ensemble de services jugés inutiles pour l'usage visé — services liés à des hyperviseurs (VirtualBox, VMware, QEMU/virt), à la connectivité mobile (ModemManager), à la géolocalisation (geoclue), à l'authentification d'entreprise (sssd), aux cartes à puce (pcscd), ainsi qu'à des composants Evolution (mail/calendrier) et GNOME Wwan/Smartcard non utilisés. Gain estimé (documenté dans le projet bootc parallèle) : environ 150 Mo de RAM.

La liste mélange volontairement des unités génériques Fedora et des unités spécifiques à Bazzite (`steamos-manager.service`, `bazzite-tdpfix.service`, `tfs-nag.service`), pour que le même script reste utilisable si un jour une machine du parc bascule sous Bazzite plutôt que Silverblue pur. C'est ce choix qui impose le `|| true` décrit en [2.3](#23-résilience-aux-échecs-set--e-et-cas-particuliers).

**b) Applications au démarrage de session** (`masquer_autostarts_gnome`) : génère des fichiers `.desktop` avec `Hidden=true` pour empêcher le lancement d'applications superflues à l'ouverture de session (Steam, notifications Evolution, agents spice/vbox/vmware, écran d'accueil Bazzite, etc.) :

```bash
for app in "${apps[@]}"; do
  backup_fichier ~/.config/autostart/"$app"
  echo "[Desktop Entry]
Type=Application
Name=$app
Exec=/bin/true
Hidden=true" > ~/.config/autostart/"$app"
done
```

### 4.9. Installation de paquets système (layering rpm-ostree)

Le *layering* rpm-ostree permet de superposer des paquets RPM classiques sur l'image immuable — l'usage recommandé étant de le réserver aux paquets réellement liés au matériel ou à la session hôte (le reste devant passer par Flatpak ou des conteneurs applicatifs, pour ne pas alourdir la base immuable).

Paquets concernés ici : `gamescope` (compositeur dédié au gaming, notamment pour Steam) et `zenity` (boîtes de dialogue graphiques, utilisées par divers scripts systèmes).

```bash
NEEDED_PKGS=(gamescope zenity)
TO_INSTALL=()
for pkg in "${NEEDED_PKGS[@]}"; do
    if ! rpm -q --quiet "$pkg"; then
        TO_INSTALL+=("$pkg")
    fi
done
if ((${#TO_INSTALL[@]})); then
    sudo rpm-ostree cancel 2>/dev/null || true
    sudo rpm-ostree install --idempotent "${TO_INSTALL[@]}"
    REBOOT_NEEDED=1
fi
```

Cette opération nécessite un redéploiement (donc un redémarrage) pour prendre effet — d'où `REBOOT_NEEDED=1`.

### 4.10. Redémarrage final

Le layering rpm-ostree et l'ajout du karg de compression BTRFS ne sont effectifs qu'après un redémarrage (nouveau déploiement). Le script part de l'hypothèse qu'un redémarrage aura lieu immédiatement après son exécution, et le déclenche donc lui-même — avec un court délai annulable :

```bash
redemarrer () {
  echo "==> Terminé."
  if [[ "${REBOOT_NEEDED:-0}" == "1" ]]; then
      echo "Un redémarrage est nécessaire (layering rpm-ostree et/ou karg appliqués au prochain déploiement)."
      echo "Redémarrage dans 10 secondes (Ctrl+C pour annuler)..."
      sleep 10
      sudo systemctl reboot
  else
      echo "Aucun redémarrage nécessaire."
  fi
}
```

`REBOOT_NEEDED` n'est positionné que par les deux étapes qui en ont réellement besoin ([4.4](#44-compression-btrfs-via-karg) et [4.9](#49-installation-de-paquets-système-layering-rpm-ostree)) — si le script est relancé alors que ces deux points sont déjà en place (cas idempotent), aucun redémarrage n'est déclenché.

## 5. Fonctions utilitaires transverses

| Fonction | Rôle |
|---|---|
| `backup_fichier` | Sauvegarde A/B d'un fichier avant écrasement (voir [2.2](#22-sauvegarde-avant-modification-schéma-ab)) |
| `arreter_maj_automatiques` | Coupe toute mise à jour automatique rpm-ostree/GNOME Software pour la durée du script, pose le `trap` de réactivation (voir [section 3](#3-neutralisation-des-mises-à-jour-automatiques)) |
| `reactiver_maj_automatiques` | Réactive le timer de mise à jour automatique ; appelée uniquement via le `trap EXIT`, jamais explicitement |

## 6. Limites connues et compromis assumés

- **Réactivation des mises à jour automatiques** : repose sur un `trap EXIT`, qui couvre les sorties normales du shell, les erreurs `set -e`, et les interruptions signal (Ctrl+C). Un arrêt plus brutal du système (perte d'alimentation, `kill -9` du processus) pendant la fenêtre où les mises à jour sont désactivées laisserait le système dans cet état — scénario jugé suffisamment rare pour ne pas justifier de mécanisme supplémentaire (ex : service de garde externe).
- **`rpm-ostree cancel` défensif, pas une attente** : le script annule une transaction en cours juste avant `kargs`/`install`, mais ne boucle pas en attente d'une disponibilité garantie. Il subsiste une fenêtre théorique (de l'ordre de la milliseconde) entre ce `cancel` et la commande suivante, où une nouvelle transaction pourrait en théorie redémarrer. Ce choix est délibéré : la priorité est d'éviter toute écriture disque non compressée pendant l'exécution du script, pas de garantir un taux de succès de 100 % au prix d'une attente.
- **`pkill -x gnome-software`** suppose que le nom du processus est exactement `gnome-software` ; à vérifier si le comportement venait à changer sur une version future de Fedora.
- **`|| true` sur les blocs `systemctl disable`/`mask`** masque toute défaillance de la commande, pas seulement le cas "unité inexistante" attendu. Une vraie erreur de syntaxe ou de permission sur ces lignes passerait donc silencieusement inaperçue.
- **Backup sans historique** : relancer le script écrase le `.backup` précédent — voir [2.2](#22-sauvegarde-avant-modification-schéma-ab). Si un historique multi-versions devient nécessaire un jour, ce mécanisme devra être revu (horodatage, ou nombre de générations à conserver).

## 7. Utilisation

```bash
chmod +x OS_config.sh
./OS_config.sh
```

Le script demande les droits `sudo` au fil de son exécution (pas de `sudo` global en tête de script). Un redémarrage est déclenché automatiquement à la fin si nécessaire (voir [4.10](#410-redémarrage-final)) — s'assurer qu'aucun travail non sauvegardé n'est en cours avant de le lancer.
