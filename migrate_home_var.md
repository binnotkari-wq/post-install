# migrate_home_var.sh — Documentation

Script bash interactif qui migre `/home` et `/var` depuis une partition ext4 vers des
sous-volumes btrfs hébergés sur un volume chiffré LUKS distinct, sur un système Ubuntu
en fonctionnement — sans passer par un mode dégradé (rescue, single user, live-USB).

---

## Contexte et motivations

### Pourquoi déporter /home et /var sur btrfs ?

Une installation Ubuntu standard place `/home` et `/var` sur la même partition ext4 que `/`.
Séparer ces deux répertoires sur un volume btrfs dédié apporte plusieurs avantages :

- **Isolation des données** : les fichiers utilisateur (`/home`) et les données variables
  du système (`/var/log`, `/var/lib`, caches, bases de données de paquets…) sont physiquement
  séparés de la racine système. Une réinstallation de l'OS ne touche pas ces données.
- **Compression transparente** : btrfs compresse à la volée avec zstd, réduisant l'espace
  occupé par les logs, les caches et les fichiers texte sans effort.
- **Chiffrement** : le volume btrfs est un conteneur LUKS. Les données utilisateur et système
  variable sont chiffrées au repos, indépendamment de la partition racine.
- **Sous-volumes indépendants** : `home` et `var` sont deux sous-volumes distincts dans le même
  conteneur LUKS. Chacun peut être snapshotté, redimensionné ou remplacé indépendamment.

### Pourquoi depuis un système en marche ?

Opérer depuis un système en marche évite de recourir à un live-USB ou à un mode rescue,
qui impliquent démontage et remontage manuel de partitions, risque d'erreur de frappe sur
les mauvais devices, et interruption complète de la session de travail. La contrepartie est
que des processus actifs écrivent dans `/home` et `/var` pendant l'opération — le script
gère cela proprement (copie rsync idempotente, montage par-dessus sans interrompre le
système).

---

## Prérequis

- Ubuntu (ou dérivé Debian) avec `systemd`
- Une partition btrfs existante, chiffrée avec LUKS2, **non encore montée**
- `rsync`, `cryptsetup`, `blkid`, `lsblk`, `findmnt` — présents par défaut sur Ubuntu
- `btrfs-progs` — installé automatiquement par le script si absent
- Droits root (`sudo ./migrate_home_var.sh`)

---

## Vue d'ensemble du déroulé

```
Étape 1  →  Sélection interactive du volume LUKS cible
Étape 2  →  Ouverture LUKS + vérification du filesystem btrfs
Étape 3  →  Création des sous-volumes home et var (si absents)
Étape 4  →  Copie rsync de /home et /var vers leurs sous-volumes
Étape 5  →  Ajout de l'entrée dans /etc/crypttab
Étape 6  →  Ajout des entrées dans /etc/fstab
Étape 7  →  Montage définitif des sous-volumes sur /home et /var
Étape 8  →  Nettoyage des anciens dossiers masqués sur l'ext4
Étape 9  →  Régénération de l'initramfs
```

---

## Détail des étapes

### Prologue — Initialisation

```bash
set -euo pipefail
```

Le script s'arrête immédiatement sur toute erreur (`-e`), sur toute variable non définie
(`-u`), et propage les erreurs à travers les pipes (`-o pipefail`). Cela empêche toute
exécution silencieuse en cas de problème partiel.

Les fonctions `info`, `ok`, `warn`, `die`, `header`, `ask` normalisent l'affichage avec
des couleurs ANSI et des préfixes explicites (`[INFO]`, `[OK]`, `[WARN]`, `[ERREUR]`, `[?]`).

```bash
trap cleanup EXIT
```

La fonction `cleanup` est enregistrée pour s'exécuter automatiquement à la sortie du script,
qu'elle soit normale ou provoquée par une erreur. Elle démonte tous les points de montage
temporaires et ferme le mapper LUKS si celui-ci a été ouvert par le script. Cela garantit
qu'aucun montage orphelin ni aucun volume LUKS ouvert ne traîne en cas d'interruption.

---

### Vérifications préalables

Le script vérifie :

1. Qu'il tourne bien en root — nécessaire pour monter des partitions et modifier `/etc`.
2. Que `btrfs-progs` est installé — s'il est absent, il l'installe via `apt-get` avant de
   continuer.
3. Que toutes les commandes nécessaires sont disponibles : `cryptsetup`, `blkid`, `lsblk`,
   `findmnt`, `mount`, `umount`, `rsync`.

---

### Étape 1 — Sélection du volume LUKS

```bash
mapfile -t LUKS_DEVS < <(blkid -t TYPE=crypto_LUKS -o device | sort)
```

`blkid` interroge le noyau pour lister tous les blocs dont le type est `crypto_LUKS`.
C'est la méthode fiable : elle ne dépend pas de noms de devices (`/dev/sda`, `/dev/vda`…)
qui varient selon le matériel et la session.

Le script identifie ensuite quel volume LUKS héberge la racine `/` en remontant la chaîne
device-mapper via `/sys/class/block/<dm>/slaves/`. Ce volume est affiché mais **exclu** de
la sélection — on ne peut pas migrer la racine sur elle-même.

Les volumes restants sont proposés sous forme de liste numérotée avec UUID et taille.
L'utilisateur saisit un numéro ; toute saisie invalide redemande.

---

### Étape 2 — Ouverture du volume LUKS

```bash
cryptsetup luksOpen "$LUKS_DEV" "$MAPPER_NAME"
```

Déchiffre le volume et crée un device virtuel dans `/dev/mapper/`. Le nom `luks-btrfs-migrate`
est utilisé temporairement pendant l'exécution du script ; il deviendra le nom permanent
inscrit dans `crypttab` et utilisé à chaque démarrage.

Après ouverture, le script vérifie que le contenu déchiffré est bien un filesystem btrfs via
`blkid`. Si ce n'est pas le cas (ext4, ntfs…), il s'arrête immédiatement.

---

### Étape 3 — Création des sous-volumes

```bash
mount -o subvolid=5 "/dev/mapper/${MAPPER_NAME}" "$TMP_BTRFS"
```

`subvolid=5` est l'identifiant réservé à la **racine du filesystem btrfs** — le niveau
zéro, au-dessus de tous les sous-volumes. Monter à ce niveau permet de voir et manipuler
tous les sous-volumes existants, et d'en créer de nouveaux, sans être confiné dans l'un
d'eux.

Pour chacun des deux sous-volumes cibles (`home`, `var`) :

- Si le sous-volume existe déjà, le script le signale et le réutilise.
- Sinon, il le crée avec `btrfs subvolume create`.

Après cette étape, le filesystem btrfs est démonté du point temporaire.

---

### Étape 4 — Copie rsync

Chaque sous-volume est monté temporairement dans un répertoire dédié
(`/home-migrate-tmp`, `/var-migrate-tmp`), puis rsync copie le contenu source.

```bash
rsync -aAXv --info=progress2 "${MP}/" "${TMP_MP}/"
```

Les options de rsync sont choisies avec soin :

| Option | Rôle |
|--------|------|
| `-a`   | Mode archive : récursif, préserve permissions, timestamps, liens symboliques, devices |
| `-A`   | Préserve les ACL (Access Control Lists) |
| `-X`   | Préserve les attributs étendus (xattrs) — indispensable pour AppArmor et les capabilities |
| `--info=progress2` | Affichage de la progression globale plutôt que fichier par fichier |

La barre oblique finale sur la source (`"${MP}/"`) est intentionnelle : elle indique à rsync
de copier le *contenu* du répertoire, pas le répertoire lui-même.

Si le sous-volume contient déjà du contenu (réexécution du script, ou sous-volume
pré-existant), l'utilisateur peut choisir de sauter la copie ou de l'écraser après
confirmation explicite.

---

### Étape 5 — /etc/crypttab

`crypttab` est le fichier qui indique à `systemd-cryptsetup` quels volumes LUKS déverrouiller
au démarrage, et comment.

```
luks-btrfs-migrate  UUID=<uuid-luks>  none  luks,discard
```

| Champ | Valeur | Signification |
|-------|--------|---------------|
| Nom mapper | `luks-btrfs-migrate` | Nom du device créé dans `/dev/mapper/` |
| UUID | UUID de la partition LUKS | Identifiant stable, indépendant du nom de device |
| Clé | `none` | Passphrase interactive (saisie au boot via Plymouth) |
| Options | `luks,discard` | Format LUKS standard + TRIM activé |

**Pourquoi `discard` ?** Sur SSD ou NVMe, le TRIM permet au firmware de récupérer les blocs
libérés. Sans cette option, le SSD ne sait pas que des blocs sont libres derrière le
chiffrement, ce qui dégrade les performances d'écriture sur le long terme.

**Pourquoi `none` suffit ?** Systemd met en cache la passphrase saisie pour le premier volume
LUKS et la réessaie automatiquement sur les volumes suivants. Si les deux volumes partagent
la même passphrase (cas typique), une seule saisie suffit au boot.

Le script sauvegarde `crypttab` avant modification (`crypttab.bak-YYYYMMDD-HHMMSS`) et
vérifie l'idempotence : si l'UUID est déjà présent, aucune modification n'est faite.

---

### Étape 6 — /etc/fstab

`fstab` indique à systemd quels filesystems monter, où, et avec quelles options.

```
UUID=<uuid-btrfs>  /home  btrfs  subvol=home,defaults,compress=zstd,noatime,x-systemd.requires=dev-mapper-luks\x2dbtrfs\x2dmigrate.device  0  0
UUID=<uuid-btrfs>  /var   btrfs  subvol=var,defaults,compress=zstd,noatime,x-systemd.requires=dev-mapper-luks\x2dbtrfs\x2dmigrate.device  0  0
```

Quelques points notables :

**UUID du filesystem btrfs, pas de la partition LUKS.** Après déchiffrement, le device
`/dev/mapper/luks-btrfs-migrate` expose le filesystem btrfs, qui a son propre UUID.
C'est cet UUID-là qui est utilisé dans `fstab` — il est stable et ne change pas.

**`subvol=home` / `subvol=var`** désigne explicitement quel sous-volume monter sur quel
point de montage. Les deux lignes partagent le même UUID de filesystem mais des sous-volumes
différents.

**`compress=zstd`** active la compression transparente. zstd est le meilleur compromis
vitesse/ratio disponible dans btrfs : les logs, fichiers de config et données textuelles
sont compressés automatiquement à l'écriture.

**`noatime`** désactive la mise à jour du timestamp d'accès (`atime`) à chaque lecture de
fichier. Sur un système actif, chaque lecture d'un fichier provoquerait sinon une écriture
(pour mettre à jour `atime`), ce qui génère du trafic disque inutile.

**`x-systemd.requires=<unit>.device`** est l'option critique. Elle indique à systemd que
ce montage dépend du device LUKS déchiffré. Sans elle, systemd pourrait tenter de monter
`/home` ou `/var` avant que le volume LUKS soit ouvert, ce qui ferait échouer le boot.
Le nom de l'unit est construit via `systemd-escape` pour respecter l'encodage systemd
des caractères spéciaux (`-` → `\x2d`).

**`0  0`** : pas de dump (`0`) et pas de fsck au boot (`0`). btrfs gère son propre journal
et n'a pas besoin de fsck traditionnel.

---

### Étape 7 — Montage définitif

```bash
mount "$MP"
```

`mount` sans device lit `/etc/fstab` pour trouver les options correspondant au point de
montage. C'est un test immédiat de la validité des entrées fstab ajoutées à l'étape
précédente — si quelque chose est incorrect (UUID, nom de sous-volume, options), l'erreur
est visible maintenant, pas au reboot.

Après montage, le contenu de chaque point de montage est affiché pour vérification visuelle.

---

### Étape 8 — Nettoyage de l'ext4

Une fois les sous-volumes btrfs montés sur `/home` et `/var`, les dossiers originaux sur
l'ext4 sont **masqués** : le point de montage les recouvre et ils ne sont plus accessibles
par les chemins habituels. Ils occupent cependant toujours de l'espace sur la partition ext4.

La technique : monter la partition ext4 racine une **deuxième fois** dans un répertoire
temporaire. Cela expose le contenu physique de la partition, y compris les dossiers masqués
par les montages actifs.

```bash
mount "$ROOT_SOURCE" "$TMP_EXT4"
# Les anciens /home et /var sont maintenant visibles sous $TMP_EXT4/home et $TMP_EXT4/var
find "$OLD_DIR" -mindepth 1 -delete
```

`find -mindepth 1 -delete` supprime récursivement le contenu d'un dossier sans supprimer
le dossier lui-même — le répertoire vide reste comme point de montage pour les prochains
boots (nécessaire pour que `mount` puisse y accrocher le sous-volume btrfs).

La suppression est proposée séparément pour `home` et `var`, avec confirmation explicite
pour chacun.

---

### Étape 9 — Régénération de l'initramfs

```bash
cd /
update-initramfs -u -k all
```

L'initramfs est l'image chargée par le bootloader avant que la racine soit montée. Elle
contient les modules et scripts nécessaires pour déverrouiller LUKS et monter `/`. Quand
`crypttab` est modifié, l'initramfs doit être régénéré pour intégrer les nouvelles entrées.

Le `cd /` préalable est important : si le répertoire courant du shell se trouve sous `/home`
ou `/var` (cas fréquent avec `sudo`), le montage des sous-volumes btrfs par-dessus ces
répertoires provoque des erreurs `getcwd() failed` dans les sous-processus lancés par
`update-initramfs`. Ces erreurs sont inoffensives mais bruyantes ; `cd /` les élimine en
plaçant le processus en terrain neutre.

---

## En cas de problème au boot

Si le système ne démarre plus correctement après exécution du script, accéder au **shell
recovery GRUB** (menu GRUB → mode recovery → root shell) et :

```bash
# Fermer le mapper si ouvert
cryptsetup luksClose luks-btrfs-migrate

# Commenter les lignes ajoutées dans crypttab et fstab
# (repérer le commentaire "# Volume btrfs — migration home et var")
nano /etc/crypttab
nano /etc/fstab

# Régénérer l'initramfs
update-initramfs -u

# Redémarrer
reboot
```

Les fichiers de sauvegarde horodatés (`/etc/fstab.bak-YYYYMMDD-HHMMSS`,
`/etc/crypttab.bak-YYYYMMDD-HHMMSS`) permettent une restauration rapide :

```bash
cp /etc/fstab.bak-YYYYMMDD-HHMMSS /etc/fstab
cp /etc/crypttab.bak-YYYYMMDD-HHMMSS /etc/crypttab
update-initramfs -u
reboot
```

---

## Vérification post-reboot

```bash
# Vérifier que les sous-volumes sont bien montés
findmnt -t btrfs

# Vérifier l'espace disponible
df -h /home /var

# Vérifier la compression active
btrfs filesystem df /home
```

La sortie de `findmnt -t btrfs` doit afficher deux lignes avec `subvol=/home` et
`subvol=/var`, toutes deux issues du même mapper LUKS.
