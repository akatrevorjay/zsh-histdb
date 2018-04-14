#!/bin/zsh

(( ${+commands[sqlite3]} )) || return

fpath+=(${0:h}/functions)

: ${HISTDB_FILE:="${HOME}/.histdb/zsh-history.db"}
# : ${HISTDB_INSTALLED_IN:=${(%):-%N}}
: ${HISTDB_INSTALLED_IN:=${0:a:h}}
typeset -ig HISTDB_AWAITING_EXIT=0
typeset -g HISTDB_FILE HISTDB_INSTALLED_IN

declare -a _BORING_COMMANDS
_BORING_COMMANDS=($'^ls$' $'^cd$' $'^ ' $'^histdb' $'^top$' $'^htop$')

autoload -Uz \
    zsh-histdb-query zsh-histdb-init zsh-histdb-update-outcome \
    histdb histdb-top histdb-sync histdb-merge

# source ${0:h}/history-timer.zsh
# source ${0:h}/histdb-interactive.zsh

