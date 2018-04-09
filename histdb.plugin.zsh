#!/bin/zsh

autoload -Uz add-zsh-hook

source ${0:h}/sqlite-history.zsh

add-zsh-hook precmd histdb-update-outcome

source ${0:h}/history-timer.zsh
source ${0:h}/histdb-interactive.zsh

