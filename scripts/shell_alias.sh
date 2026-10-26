#!/usr/bin/env bash

set -euo pipefail

echo "==> Mise en place des alias"

if [[ ! -f "$HOME/.bashrc" ]]; then
    cp /etc/skel/.bashrc "$HOME/.bashrc"
fi

# Sauvegarde un fichier existant en .backup avant modification.
backup_fichier () {
    local fichier="$1"
    local besoin_sudo="${2:-}"

    local backup="${fichier}.backup"

    if [[ "$besoin_sudo" == "sudo" ]]; then
        # Ne faire le backup que si le backup n'existe pas déjà
        if sudo test -f "$fichier" && ! sudo test -f "$backup"; then
            sudo cp -a "$fichier" "$backup"
            echo "  ↳ Backup créé : ${backup}"
        fi
    else
        if [[ -f "$fichier" ]] && [[ ! -f "$backup" ]]; then
            cp -a "$fichier" "$backup"
            echo "  ↳ Backup créé : ${backup}"
        fi
    fi
}

# Idempotence : ajoute une ligne à un fichier seulement si elle n'y figure pas déjà.
ajouter_ligne_si_absente () {
    local ligne="$1" fichier="$2"
    if ! grep -qxF "$ligne" "$fichier" 2>/dev/null; then
        backup_fichier "$fichier"
        echo "$ligne" >> "$fichier"
    fi
}

ajouter_ligne_si_absente "alias bh='$HOME/Git/scripts/bash-history-export.sh'" "$HOME/.bashrc"
ajouter_ligne_si_absente "alias gs='$HOME/Git/scripts/git-sync.sh'" "$HOME/.bashrc"
# alias gemma='llama-cli --model "/cargo/local_cache/LLM/gemma-3-4b-it-Q8_0.gguf" --conversation --system-prompt "Tu es un assistant compréhensif pour la vie quotidienne : ménage, jardin, travaux, mécanique." --no-mmap --ctx-size 4096'
# alias qwen='llama-cli --model "/cargo/local_cache/LLM/Qwen2.5-Coder-3B-Instruct-abliterated-Q4_K_M.gguf" --conversation --system-prompt "Tu es un assistant concis en ingénierie des systèmes linux, scripting, développement." --no-mmap --ctx-size 4096'
# alias llama='llama-cli --model "/cargo/local_cache/LLM/Llama-3.2-3B-Instruct-Q4_K_M.gguf" --conversation --system-prompt "Tu es un assistant personnel pour aider à explorer de nouveaux concepts." --no-mmap --ctx-size 4096'

echo "✅ Alias mis en place avec succès."