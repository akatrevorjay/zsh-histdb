(( ${+commands[sqlite3]} )) || return

typeset -g HISTDB_QUERY=""
typeset -g HISTDB_FILE="${HOME}/.histdb/zsh-history.db"
typeset -g HISTDB_SESSION=""
typeset -g HISTDB_HOST=""
# typeset -g HISTDB_INSTALLED_IN="${(%):-%N}"
# typeset -g HISTDB_INSTALLED_IN=${0:A:h}
typeset -g HISTDB_AWAITING_EXIT=0

zsh-histdb-query () {
    sqlite3 ${HISTDB_FILE} "$@"
    local rv=$?
    [[ $rv -eq 0 ]] || echo "[$0] error in: $*" >&2
    return $rv
}

zsh-histdb-init () {
    if ! [[ -e ${HISTDB_FILE} ]]; then
        local hist_dir=${HISTDB_FILE:h}
        mkdir -pv -- $hist_dir

        zsh-histdb-query <<-EOF
create table commands (argv text, unique(argv) on conflict ignore);
create table places   (host text, dir text, unique(host, dir) on conflict ignore);
create table history  (session int,
                       command_id int references commands (rowid),
                       place_id int references places (rowid),
                       exit_status int,
                       start_time int,
                       duration int);
EOF
    fi

    if [[ -z ${HISTDB_SESSION} ]]; then
        HISTDB_HOST=${(qqq)HOST}

        HISTDB_SESSION=$(zsh-histdb-query "select 1+max(session) from history inner join places on places.rowid=history.place_id where places.host = ${HISTDB_HOST}")
        : ${HISTDB_SESSION:=0}
        readonly HISTDB_SESSION
    fi
}

declare -a _BORING_COMMANDS
_BORING_COMMANDS=($'^ls$' $'^cd$' $'^ ' $'^histdb' $'^top$' $'^htop$')

histdb-update-outcome () {
    local retval=$?
    local finished=$(date +%s)
    if [[ $HISTDB_AWAITING_EXIT == 1 ]]; then
        zsh-histdb-init
        zsh-histdb-query "update history set exit_status = ${retval}, duration = ${finished} - start_time
where rowid = (select max(rowid) from history) and session = ${HISTDB_SESSION}"
        HISTDB_AWAITING_EXIT=0
    fi
}

zshaddhistory () {
    local cmd="${1[0, -2]}"
    [[ -n $cmd ]] || return 0

    local boring
    for boring in ${(@)_BORING_COMMANDS}; do
        if [[ $cmd =~ $boring ]]; then
            return 0
        fi
    done

    local started=$(date +%s)
    zsh-histdb-init

    zsh-histdb-query \
      "insert into commands (argv) values (${(qqq)cmd});
      insert into places   (host, dir) values (${HISTDB_HOST}, ${(qqq)pwd});
      insert into history
        (session, command_id, place_id, start_time)
      select
        ${HISTDB_SESSION},
        commands.rowid,
        places.rowid,
        ${started}
      from
        commands, places
      where
        commands.argv = ${(qqq)cmd} and
        places.host = ${HISTDB_HOST} and
        places.dir = ${(qqq)pwd}
      ;"

    HISTDB_AWAITING_EXIT=1

    return 0
}

histdb-top () {
    zsh-histdb-init
    local field
    local join
    local table

    argv=(${1:-cmd} "${@:2}")

    case $1 in
        dir)
            field=places.dir
            join='places.rowid = history.place_id'
            table=places
            ;;

        cmd|*)
            field=commands.argv
            join='commands.rowid = history.command_id'
            table=commands
            ;;
    esac

    zsh-histdb-query \
      -column \
      -header "select count(*) as count, places.host, $field as cmd
              from history
                left join commands
                  on history.command_id=commands.rowid
                left join places
                  on history.place_id=places.rowid
                group by
                  places.host,
                  $field
                order by count(*)"
}

histdb-sync () {
    zsh-histdb-init

    local hist_dir=${HISTDB_FILE:h}
    [[ -d $hist_dir ]] || return

    (
        cd -- $hist_dir || return 1

        local g_is_inside_work_tree=$(git rev-parse --is-inside-work-tree)
        local g_show_toplevel=$(git rev-parse --show-toplevel)

        if [[ $g_is_inside_work_tree != 'true' ]] || [[ $g_show_toplevel != $PWD ]]; then
            git init

            git config merge.histdb.driver "${(qqq)HISTDB_INSTALLED_IN}/histdb-merge %O %A %B"

            printf '%s merge=histdb\n' ${(qqq)HISTDB_FILE:t} >> ./.gitattributes
            git add .gitattributes

            git add ${HISTDB_FILE:t}
        fi

        git commit -am "history" && git pull --no-edit && git push
    )
}

histdb () {
    zsh-histdb-init
    local -a opts
    local -a hosts
    local -a indirs
    local -a atdirs
    local -a sessions

    zparseopts -E -D -a opts \
               -host+::=hosts \
               -in+::=indirs \
               -at+::=atdirs \
               -forget \
               -detail \
               -exact \
               d h -help \
               s+::=sessions \
               -from:- -until:- -limit:-

    local usage="usage:$0 terms [--host] [--in] [--at] [-s n]+* [--from] [--until] [--limit] [--forget] [--detail]
    --host    print the host column and show all hosts (otherwise current host)
    --host x  find entries from host x
    --in      find only entries run in the current dir or below
    --in x    find only entries in directory x or below
    --at      like --in, but excluding subdirectories
    -s n      only show session n
    -d        debug output query that will be run
    --detail  show details
    --forget  forget everything which matches in the history
    --exact   don't match substrings
    --from x  only show commands after date x (sqlite date parser)
    --until x only show commands before date x (sqlite date parser)
    --limit n only show n rows. defaults to $LINES or 25"

    local selcols="session as ses, dir"
    local cols="session, replace(places.dir, '$HOME', '~') as dir"
    local where="not (commands.argv like 'histdb%')"
    if [[ -p /dev/stdout ]]; then
        local limit=""
    else
        local limit="${$((LINES - 4)):-25}"
    fi

    local forget="0"
    local exact=0

    if (( ${#hosts} )); then
        local hostwhere=""
        local host=""
        for host ($hosts); do
            host="${${host#--host}#=}"
            hostwhere="${hostwhere}${host:+${hostwhere:+ or }places.host=${(qqq)host}}"
        done
        where="${where}${hostwhere:+ and (${hostwhere})}"
        cols="${cols}, places.host as host"
        selcols="${selcols}, host"
    else
        where="${where} and places.host=${HISTDB_HOST}"
    fi

    if (( ${#indirs} + ${#atdirs} )); then
        local dirwhere=""
        local dir=""
        local match=''

        for dir ($indirs); do
            dir=${${${dir#--in}#=}:-$PWD}
            match="$dir%"
            dirwhere="${dirwhere}${dirwhere:+ or }places.dir like ${(qqq)match}"
        done

        for dir ($atdirs); do
            dir="${${${dir#--at}#=}:-$PWD}"
            dirwhere="${dirwhere}${dirwhere:+ or }places.dir = ${(qqq)dir}"
        done

        where="${where}${dirwhere:+ and (${dirwhere})}"
    fi

    if (( ${#sessions} )); then
        local sin=""
        local ses=""
        for ses ($sessions); do
            ses="${${${ses#-s}#=}:-${HISTDB_SESSION}}"
            sin="${sin}${sin:+, }$ses"
        done
        where="${where}${sin:+ and session in ($sin)}"
    fi

    local debug=0
    local opt=""
    for opt ($opts); do
        case $opt in
            --from*)
                local from=${opt#--from}
                case $from in
                    -*)
                        from="datetime('now', '$from')"
                        ;;
                    today)
                        from="datetime('now', 'start of day')"
                        ;;
                    yesterday)
                        from="datetime('now', 'start of day', '-1 day')"
                        ;;
                esac
                where="${where} and datetime(start_time, 'unixepoch') >= $from"
            ;;
            --until*)
                local until=${opt#--until}
                case $until in
                    -*)
                        until="datetime('now', '$until')"
                        ;;
                    today)
                        until="datetime('now', 'start of day')"
                        ;;
                    yesterday)
                        until="datetime('now', 'start of day', '-1 day')"
                        ;;
                esac
                where="${where} and datetime(start_time, 'unixepoch') <= $until"
                ;;
            -d)
                debug=1
                ;;
            --detail)
                cols="${cols}, exit_status, duration "
                selcols="${selcols}, exit_status as [?],duration as secs "
                ;;
            -h|--help)
                echo "$usage"
                return 0
                ;;
            --forget)
                forget=1
                ;;
            --exact)
                exact=1
                ;;
            --limit*)
                limit=${opt#--limit}
                ;;
        esac
    done

    if [[ -n "$*" ]]; then
        if [[ $exact -eq 0 ]]; then
            local match="*${*}*"
            where="${where} and commands.argv glob ${(qqq)match}"
        else
            where="${where} and commands.argv = ${(qqq)*}"
        fi
    fi

    if [[ $forget -gt 0 ]]; then
        limit=""
    fi
    cols+=", commands.argv as argv, max(start_time) as max_start"

    local mst="datetime(max_start, 'unixepoch')"
    local dst="datetime('now', 'start of day')"
    local timecol="strftime(case when $mst > $dst then '%H:%M' else '%d/%m' end, max_start, 'unixepoch', 'localtime') as time"

    selcols="${timecol}, ${selcols}, argv as cmd"

    local query="select ${selcols} from (select ${cols}
from
  history
  left join commands on history.command_id = commands.rowid
  left join places on history.place_id = places.rowid
where ${where}
group by history.command_id, history.place_id
order by max_start desc
${limit:+limit $limit}) order by max_start asc"

    ## min max date?
    local count_query="select count(*) from (select ${cols}
from
  history
  left join commands on history.command_id = commands.rowid
  left join places on history.place_id = places.rowid
where ${where}
group by history.command_id, history.place_id
order by max_start desc) order by max_start asc"

    if [[ $debug = 1 ]]; then
        echo "$query"
    else
        local count=$(zsh-histdb-query "$count_query")
        if [[ -p /dev/stdout ]]; then
            buffer() {
                ## this runs out of memory for big files I think perl -e 'local $/; my $stdin = <STDIN>; print $stdin;'
                temp=$(mktemp)
                cat >! "$temp"
                cat -- "$temp"
                rm -f -- "$temp"
            }
        else
            buffer() {
                cat
            }
        fi

        zsh-histdb-query -header -column $query

        [[ -n $limit ]] && [[ $limit -lt $count ]] && echo "(showing $limit of $count results)"
    fi

    if [[ $forget -gt 0 ]]; then
        read -q "REPLY?Forget all these results? [y/n] "
        if [[ $REPLY =~ "[yY]" ]]; then
            zsh-histdb-query "delete from history where
history.rowid in (
select history.rowid from
history
  left join commands on history.command_id = commands.rowid
  left join places on history.place_id = places.rowid
where ${where})"
            zsh-histdb-query "delete from commands where commands.rowid not in (select distinct history.command_id from history)"
        fi
    fi
}
