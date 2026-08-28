#!/usr/bin/env bash
# /etc/profile.d/10-environment.sh

# ── Historique ────────────────────────────────────────────────
export HISTSIZE=100000
export HISTFILESIZE=100000
export HISTTIMEFORMAT="%s "

# ── Prompt, historique immédiat ───────────────────────────────
if [[ $- == *i* ]]; then
    PS1='\[\e[01;32m\][\u@\h\[\e[00m\]:\[\e[01;34m\]\w\[\e[01;32m\]]\$\[\e[00m\] '
    shopt -s histappend
    echo "# SESSION $(date +%s)" >> "$HISTFILE"
    PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
fi
