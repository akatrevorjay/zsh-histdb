#!/bin/zsh

autoload -Uz source-with-force add-zsh-hook

source ${0:h}/sqlite-history.zsh

add-zsh-hook precmd histdb-update-outcome

