# Documentation — `post-install-environnement.sh`

Script de post-installation « environnement » : mise en place des outils, préférences et applications d'un poste de travail. Distinct du script `OS_config.sh` (réglages bas niveau de l'OS) — celui-ci ne touche à aucune donnée personnelle et se concentre sur l'environnement applicatif.

## Sommaire

1. [Principes généraux](#1-principes-généraux)
   - 1.1 [Sauvegarde des fichiers modifiés](#11-sauvegarde-des-fichiers-modifiés)
   - 1.2 [Idempotence](#12-idempotence)
   - 1.3 [Ordre d'exécution](#13-ordre-dexécution)
2. [Préférences système](#2-préférences-système)
3. [Alias shell](#3-alias-shell)
4. [Dépôt GitHub personnel](#4-dépôt-github-personnel)
5. [Homebrew](#5-homebrew)
6. [Flatpaks](#6-flatpaks)
7. [Llama.cpp](#7-llamacpp)
8. [Atomic Image Builder](#8-atomic-image-builder)
9. [Distrobox (binaire)](#9-distrobox-binaire)
10. [Distrobox `fedora-tools`](#10-distrobox-fedora-tools)
11. [Téléchargement des LLM](#11-téléchargement-des-llm)
12. [Bugs corrigés par rapport à la version initiale](#12-bugs-corrigés-par-rapport-à-la-version-initiale)

---

## 1. Principes généraux

### 1.1 Sauvegarde des fichiers modifiés

Toute écriture sur un fichier préexistant (téléchargement qui écrase une config, ajout de ligne, édition de `/etc/sudoers`) passe par `sauvegarder_fichier()`, qui copie l'ancienne version en `<fichier>.backup` avant modification.

- Le `.backup` est **écrasé à chaque run** : ce n'est pas un historique daté, seulement un filet de sécurité contre la dernière écriture en date — même logique que dans `OS_config.sh`.
- Une variante `avec_sudo` existe pour les fichiers appartenant à root (`/etc/sudoers`, `/etc/firefox/policies/...`), car un `cp` non privilégié échouerait dessus.
- Appelée automatiquement par `telecharger_fichier()` et `ajouter_ligne_si_absente()` ; appelée manuellement là où le script modifie un fichier sans passer par ces deux fonctions (`/etc/sudoers`, `~/.local/bin/aib`).

### 1.2 Idempotence

Objectif : pouvoir relancer le script autant de fois que nécessaire sans effet cumulatif (lignes dupliquées, erreurs sur des ressources déjà présentes).

| Zone à risque | Mécanisme retenu |
|---|---|
| Ajouts à `~/.bashrc` (alias, `eval brew shellenv`) | `ajouter_ligne_si_absente()` : `grep -qxF` avant `echo >>` |
| `sed` sur `/etc/sudoers` (secure_path Homebrew) | vérification `grep -q "linuxbrew"` avant d'exécuter le `sed` |
| Installation de Brew / llama / distrobox (curl \| sh) | `command -v` avant de relancer l'installeur distant |
| Téléchargement de fichiers de config (`telecharger_fichier`) | pas de garde nécessaire : le fichier est simplement re-synchronisé avec la source à chaque run, ce qui est déjà un résultat idempotent |
| `flatpak install`, `dnf install`, `distrobox create` | idempotents nativement par les outils eux-mêmes — aucune garde ajoutée |
| Export de binaires distrobox (`distrobox-export`) | idempotent nativement (écrase le lien existant) |

Contrairement à `OS_config.sh`, ce script ne modifie aucun paramètre kernel (kargs) ni service systemd critique : il n'y a donc pas eu besoin de mécanisme de type `trap` de réactivation ou de `rpm-ostree cancel` défensif.

### 1.3 Ordre d'exécution

Défini par `executer_logique()`, dans cet ordre : préférences → alias → repo GitHub → Homebrew → Flatpaks → llama.cpp → Atomic Image Builder → distrobox (binaire) → distrobox `fedora-tools` → téléchargement des LLM.

Les numéros affichés dans les `echo` de chaque fonction (`"1. ..."`, `"2. ..."`, etc.) suivent désormais cet ordre réel d'exécution (dans la version initiale, la numérotation des `echo` ne correspondait pas à l'ordre d'appel réel).

---

## 2. Préférences système

Fonction : `mettre_en_place_preferences`

Télécharge, depuis le dépôt `binnotkari-wq/post-install` (dossier `system_files`), un ensemble de fichiers de configuration :

- Policies Firefox (`policies.json`), déposées à deux emplacements : celui utilisé par Firefox Flatpak (`/var/lib/flatpak/extension/.../policies`) et celui utilisé par un Firefox natif (`/etc/firefox/policies`).
- Variables d'environnement globales (`/etc/profile.d/10-environment.sh`).
- Réglages dconf par défaut (`/etc/dconf/db/local.d/00-defaults`, `/etc/dconf/profile/user`), activés ensuite via `dconf update`.
- Modèles de fichiers personnels (`$HOME/Modèles/`) : Markdown, texte, script.

Chaque fichier passe par `telecharger_fichier()`, qui centralise sauvegarde + téléchargement + permissions (`644` pour les configs, `755` pour le script exécutable), là où la version initiale n'appliquait des permissions qu'à deux fichiers sur huit.

Un commentaire sur les `extraGroups` NixOS (`libvirtd`, `kvm`) est laissé en l'état : il s'agit d'un pense-bête, pas d'une action exécutée par ce script (le paramètre est déclaratif côté configuration NixOS elle-même).

## 3. Alias shell

Fonction : `mettre_en_place_alias`

Ajoute deux alias (`bh` pour l'export d'historique bash, `gs` pour la synchronisation git) dans `~/.bashrc`, via `ajouter_ligne_si_absente()` pour éviter la duplication au fil des runs.

Trois alias vers des modèles LLM locaux (gemma, qwen, llama) sont laissés en commentaire — activables manuellement selon la machine et les modèles réellement téléchargés (cf. section 11).

## 4. Dépôt GitHub personnel

Fonction : `mettre_en_place_repo_github`

Récupère et exécute `git-sync.sh` depuis le dépôt `binnotkari-wq/scripts`, chargé de cloner/synchroniser le dépôt de scripts personnels. L'idempotence de cette étape dépend entièrement du comportement de `git-sync.sh` lui-même (hors périmètre de ce script).

## 5. Homebrew

Fonction : `installer_brew`

1. Installe Homebrew uniquement si absent (`command -v brew` **et** test de l'exécutable `/home/linuxbrew/.linuxbrew/bin/brew`, car juste après une installation fraîche `brew` n'est pas encore dans le `PATH` de la session courante).
2. Ajoute le chemin Homebrew au `secure_path` de `/etc/sudoers`, uniquement s'il n'y figure pas déjà.
3. Ajoute la ligne `eval "$(brew shellenv bash)"` à `~/.bashrc`, une seule fois.
4. Réordonne le `PATH` de la session courante pour que les binaires système (`/usr/bin`, `/bin`, etc.) restent prioritaires sur ceux de Homebrew — évite qu'un paquet Homebrew masque un équivalent système attendu par d'autres scripts.
5. Installe les paquets listés dans `APPS_BREW` (actuellement `cosign` seul — les autres candidats sont documentés en commentaire avec la raison de leur exclusion : disponibles autrement, en standalone ou en distrobox Fedora).

## 6. Flatpaks

Fonction : `installer_flatpaks`

- Ajoute le remote Flathub (`--if-not-exists`, idempotent nativement).
- Installe un socle de flatpaks communs à toutes les machines (`BASE_FLATPAKS`).
- Installe en plus, **uniquement sur variante atomique** (détection via `/etc/os-release` : silverblue/kinoite/bazzite), les flatpaks qui doivent rester exclusifs à ces systèmes — typiquement des outils normalement installés nativement sur NixOS, mais indisponibles ou moins adaptés en Flatpak/distrobox sur une base atomique classique (ex. `LACT` pour le contrôle GPU AMD).
- Nettoie les flatpaks orphelins (`flatpak uninstall --unused`).

## 7. Llama.cpp

Fonction : `installer_llama`

Installe `llama.cpp` (build Vulkan, non disponible en `.rpm` pour distrobox) via l'installeur distant officiel, uniquement si `llama-cli` n'est pas déjà présent sur le système.

## 8. Atomic Image Builder

Fonction : `installer_AIB`

Télécharge le script `aib` (Atomic Image Builder, non disponible en `.rpm` pour distrobox) dans `~/.local/bin`. Contrairement aux autres installeurs, il n'y a pas de garde `command -v` : le fichier est simplement retéléchargé et réécrasé à chaque run (avec sauvegarde de la version précédente), ce qui reste un comportement idempotent et garantit de toujours avoir la dernière version du script.

## 9. Distrobox (binaire)

Fonction : `installer_distrobox`

Installe le binaire `distrobox` lui-même (canal *legacy*, version stable), uniquement si absent.

## 10. Distrobox `fedora-tools`

Fonction : `creer_distrobox_fedora-tools`

Crée (si elle n'existe pas déjà — vérifié via `distrobox list`) une distrobox basée sur `fedora:latest`, y installe un ensemble d'utilitaires CLI (`PACKAGES`) absents ou moins pratiques nativement sur les systèmes cibles, puis exporte vers l'hôte (`~/.local/bin`) une liste de binaires précise (`BINARIES`) — notamment les nombreux outils `libva-utils` (VA-API) utiles pour diagnostiquer l'accélération vidéo matérielle.

`dnf install -y` et `distrobox-export` sont idempotents par construction (dnf ignore les paquets déjà installés ; l'export écrase le lien existant), donc aucune garde supplémentaire n'a été ajoutée ici.

## 11. Téléchargement des LLM

Fonction : `telecharger_llm`

Non implémentée à ce stade — trois modèles sont identifiés en commentaire (Gemma 3 4B, Qwen2.5-Coder 3B abliterated, Llama 3.2 3B), destinés à un téléchargement via `aria2c` une fois la logique écrite. Le corps de fonction contient un `:` (no-op) pour rester syntaxiquement valide en bash tant que l'implémentation n'est pas faite (cf. section 12).

---

## 12. Bugs corrigés par rapport à la version initiale

| Bug | Symptôme | Correction |
|---|---|---|
| `set -oue pipefail` | `set` échouait immédiatement (`ue: invalid option name`) : `-o` consommait `ue` comme argument | `set -ueo pipefail` (option `-o` placée en dernier) |
| `telecharger_llm` à corps vide | Erreur de syntaxe bash (`syntax error near unexpected token` } '`) : un bloc `{ }` composé uniquement de commentaires est vide au sens du parseur | Ajout d'un `:` (no-op) |
| `$HOME/Modèles` non créé | Échec silencieux des `curl` écrivant dans ce dossier | Ajout de `mkdir -p "$HOME/Modèles"` |
| `"Fichier Fichier texte.txt"` | Nom de fichier local dupliqué par erreur de copier-coller | Corrigé en `"Fichier texte.txt"` |
| `chmod` incomplet | Seuls 2 fichiers sur 8 téléchargés recevaient des permissions explicites | Permissions systématiques via `telecharger_fichier()` |
| Alias/`eval` ajoutés à `~/.bashrc` sans garde | Duplication de lignes à chaque exécution du script | `ajouter_ligne_si_absente()` |
| `sed` sur `/etc/sudoers` sans garde | Le chemin Homebrew aurait pu être réinjecté à chaque run | Vérification préalable par `grep` |
| Brew/llama/distrobox réinstallés à chaque run | Ré-exécution inutile (et bruyante) des installeurs distants | Garde `command -v` avant installation |
| Numérotation des étapes (`echo "N. ..."`) | Ne correspondait pas à l'ordre réel d'exécution | Renumérotée de 1 à 10 dans l'ordre de `executer_logique` |

---

*Document généré à partir du script `post-install-environnement.sh`, sur le même modèle que la documentation de `OS_config.sh`.*
