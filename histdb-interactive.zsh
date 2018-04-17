#!/bin/zsh

typeset -g HISTDB_ISEARCH_N
typeset -g HISTDB_ISEARCH_MATCH
typeset -g HISTDB_ISEARCH_DIR
typeset -g HISTDB_ISEARCH_HOST
typeset -g HISTDB_ISEARCH_DATE
typeset -g HISTDB_ISEARCH_MATCH_END

typeset -g HISTDB_ISEARCH_THIS_HOST=1
typeset -g HISTDB_ISEARCH_THIS_DIR=0
typeset -g HISTDB_ISEARCH_LAST_QUERY=""
typeset -g HISTDB_ISEARCH_LAST_N=""

# TODO Show more info about match (n, date, pwd, host)
# TODO Keys to limit match?

# make a keymap for histdb isearch
bindkey -N histdb-isearch main

zsh-histdb-isearch_query () {
    if [[ -z $BUFFER ]]; then
       HISTDB_ISEARCH_MATCH=""
       return
    fi

    local new_query="$BUFFER $HISTDB_ISEARCH_THIS_HOST $HISTDB_ISEARCH_THIS_DIR"
    if [[ $new_query == $HISTDB_ISEARCH_LAST_QUERY ]] && [[ $HISTDB_ISEARCH_N == $HISTDB_ISEARCH_LAST_N ]]; then
        return
    elif [[ $new_query != $HISTDB_ISEARCH_LAST_QUERY ]]; then
        HISTDB_ISEARCH_N=0
    fi

    HISTDB_ISEARCH_LAST_QUERY=$new_query
    HISTDB_ISEARCH_LAST_N=HISTDB_ISEARCH_N

    if (( $HISTDB_ISEARCH_N < 0 )); then
        local maxmin="min"
        local ascdesc="asc"
        local offset=$(( - $HISTDB_ISEARCH_N ))
    else
        local maxmin="max"
        local ascdesc="desc"
        local offset=$(( $HISTDB_ISEARCH_N ))
    fi

    if [[ $HISTDB_ISEARCH_THIS_DIR == 1 ]]; then
        local match="$PWD%"
        local where_dir="and places.dir like ${(qqq)match}'"
    else
        local where_dir=""
    fi


    if [[ $HISTDB_ISEARCH_THIS_HOST == 1 ]]; then
        local where_host="and places.host = ${(qqq)HOST}"
    else
        local where_host=""
    fi

    local match="*${BUFFER}*"
    local query="select
commands.argv,
places.dir,
places.host,
datetime(max(history.start_time), 'unixepoch')
from history left join commands
on history.command_id = commands.rowid
left join places
on history.place_id = places.rowid
where commands.argv glob ${(qqq)match}
${where_host}
${where_dir}
group by commands.argv, places.dir, places.host
order by ${maxmin}(history.start_time) ${ascdesc}
limit 1
offset ${offset}"

    local result=$(zsh-histdb-query -separator $'\n' "$query")
    local lines=("${(f)result}")
    HISTDB_ISEARCH_DATE=${lines[-1]}
    HISTDB_ISEARCH_HOST=${lines[-2]}
    HISTDB_ISEARCH_DIR=${lines[-3]}
    lines[-1]=()
    lines[-1]=()
    lines[-1]=()
    HISTDB_ISEARCH_MATCH=${(F)lines}
}

zsh-histdb-isearch_display () {
    if [[ $HISTDB_ISEARCH_THIS_HOST == 1 ]]; then
        local host_bit=" h"
    else
        local host_bit=""
    fi
    if [[ $HISTDB_ISEARCH_THIS_DIR == 1 ]]; then
        local dir_bit=" d"
    else
        local dir_bit=""
    fi
    local top_bit="histdb ${HISTDB_ISEARCH_N}${host_bit}${dir_bit}: "
    if [[ -z ${HISTDB_ISEARCH_MATCH} ]]; then
        PREDISPLAY="(no match)
$top_bit"
    else
        local qbuffer="${(b)BUFFER}"
        qbuffer="${${qbuffer//\\\*/*}//\\\?/?}"
        local match_len="${#HISTDB_ISEARCH_MATCH}"
        local prefix="${HISTDB_ISEARCH_MATCH%%${~qbuffer}*}"
        local prefix_len="${#prefix}"
        local suffix_len="${#${HISTDB_ISEARCH_MATCH:${prefix_len}}##${~qbuffer}}"
        local match_end=$(( $match_len - $suffix_len ))
        HISTDB_ISEARCH_MATCH_END=${match_end}

        if [[ $HISTDB_ISEARCH_HOST == $HOST ]]; then
            local host=""
        else
            local host="
  host: $HISTDB_ISEARCH_HOST"
        fi
        region_highlight=("P${prefix_len} ${match_end} underline")
        PREDISPLAY="${HISTDB_ISEARCH_MATCH}
→ in ${HISTDB_ISEARCH_DIR}$host
→ on ${HISTDB_ISEARCH_DATE}
$top_bit"
    fi
}

zsh-histdb-isearch-up () {
    HISTDB_ISEARCH_N=$(( $HISTDB_ISEARCH_N + 1 ))
}

zsh-histdb-isearch-down () {
    HISTDB_ISEARCH_N=$(( $HISTDB_ISEARCH_N - 1 ))
}

zle -N self-insertzsh-histdb-isearch

zsh-histdb-line_redraw () {
    zsh-histdb-isearch_query
    zsh-histdb-isearch_display
}

zsh-histdb-isearch () {
    local old_buffer=${BUFFER}
    local old_cursor=${CURSOR}
    HISTDB_ISEARCH_N=0
    echo -ne "\e[4 q" # switch to underline cursor

    zle -K histdb-isearch
    zle -N zle-line-pre-redraw zsh-histdb-line_redraw
    zsh-histdb-isearch_query
    zsh-histdb-isearch_display
    zle recursive-edit; local stat=$?
    zle -D zle-line-pre-redraw # TODO push/pop zle-line-pre-redraw and
                               # self-insert, rather than nuking

    zle -K main
    PREDISPLAY=""
    region_highlight=()

    echo -ne "\e[1 q" #box cursor

    if ! (( stat )); then
        BUFFER="${HISTDB_ISEARCH_MATCH}"
        CURSOR="${HISTDB_ISEARCH_MATCH_END}"
    else
        BUFFER=${old_buffer}
        CURSOR=${old_cursor}
    fi

    return 0
}

# this will work outside histdb-isearch if you want
# so you can recover from history and then cd afterwards
zsh-histdb-isearch-cd () {
    if [[ -d ${HISTDB_ISEARCH_DIR} ]]; then
        cd "${HISTDB_ISEARCH_DIR}"
        zle reset-prompt
    fi
}

zsh-histdb-isearch-toggle-host () {
    if [[ $HISTDB_ISEARCH_THIS_HOST == 1 ]]; then
        HISTDB_ISEARCH_THIS_HOST=0
    else
        HISTDB_ISEARCH_THIS_HOST=1
    fi
}

zsh-histdb-isearch-toggle-dir () {
    if [[ $HISTDB_ISEARCH_THIS_DIR == 1 ]]; then
        HISTDB_ISEARCH_THIS_DIR=0
    else
        HISTDB_ISEARCH_THIS_DIR=1
    fi
}

zle -N zsh-histdb-isearch-up
zle -N zsh-histdb-isearch-down
zle -N zsh-histdb-isearch
zle -N zsh-histdb-isearch-cd
zle -N zsh-histdb-isearch-toggle-dir
zle -N zsh-histdb-isearch-toggle-host

bindkey -M histdb-isearch '' zsh-histdb-isearch-up
bindkey -M histdb-isearch '^[[A' zsh-histdb-isearch-up

bindkey -M histdb-isearch '' zsh-histdb-isearch-down
bindkey -M histdb-isearch '^[[B' zsh-histdb-isearch-down

bindkey -M histdb-isearch '^[j' zsh-histdb-isearch-cd

bindkey -M histdb-isearch '^[h' zsh-histdb-isearch-toggle-host
bindkey -M histdb-isearch '^[d' zsh-histdb-isearch-toggle-dir

# because we are using BUFFER for output, we have to reimplement
# pretty much the whole set of buffer editing operations
