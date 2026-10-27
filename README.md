# post-install

Kit de post installation, configuration OS et environnement pour Ubuntu et distributions basées sur Fedora Atomic. Aucune donnée personnelle.

## Exécution

```bash
wget -qO /tmp/post-install.zip https://github.com/binnotkari-wq/post-install/archive/refs/heads/main.zip && \
unzip -q /tmp/post-install.zip -d /tmp/ && \
mv /tmp/post-install-main /tmp/post-install && \
wget -qO- https://github.com/casey/just/releases/download/1.59.0/just-1.59.0-x86_64-unknown-linux-musl.tar.gz | tar -xz -C /tmp/post-install just && \
cd /tmp/post-install && ./just
```

Actions de ces commandes : 

- Télécharge l’archive zip de ce repo dans /tmp/
- La décompresse dans /tmp/post-install-main/
- Renomme en /tmp/post-install/
- Télécharge et décompresse l’archive de just, en extrayant uniquement l’exécutable just directement dans /tmp/post-install/
- Se place dans le dossier et lance ./just

Le just extrait dans le même dossier que le justfile suffit, pas besoin de l’installer dans le PATH.