#!/bin/zsh

(( ${+commands[sqlite3]} )) || return

fpath+=(${0:h}/functions)

: ${HISTDB_FILE:="${HOME}/.histdb/zsh-history.db"}
# : ${HISTDB_INSTALLED_IN:=${(%):-%N}}
: ${HISTDB_INSTALLED_IN:=${0:a:h}}

autoload -Uz \
    zsh-histdb-init \
    histdb histdb-top histdb-sync histdb-merge


zsh-histdb-init

# source ${0:h}/histdb-interactive.zsh

