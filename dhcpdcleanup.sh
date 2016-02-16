#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o noglob
set -o pipefail

SELF="$(basename $0)"
DRYRUN=${DRYRUN:-"no"}
REMOVE=${REMOVE:-"no"}
SILENT=${SILENT:-"yes"}
OVERWRITE=${OVERWRITE:-"no"}
TRACE=${TRACE:-no}
[ "$TRACE" != "no" ] && set -x

usage () {
    cat <<-EOU
    Usage: ${SELF} FILE
    
    Sanitize dhcpd.conf file

    Environment (default):
    DRYRUN=[yes|no]     Don't touch the file (no)
    OVERWRITE=[yes|no]  Overwrite original file (no)
    REMOVE=[yes|no]     Don't correct the error, remove the line (no)
    SILENT=[yes|no]     Don't display catched lines (yes)
    TRACE=[yes|no]      Trace script (no)

    Example:
    OVERWRITE=yes ./${SELF} ./dhcpd.conf
    EOU
}

fix_pattern () {
    typeset pattern="$1"; shift
    typeset ifile="$1"; shift

    [ "$DRYRUN" != "yes" ] && {
        sed --in-place --regexp-extended "$pattern" "$ifile"
    } || return 0
}

remove_pattern () {
    typeset pattern="$1"; shift
    typeset ifile="$1"; shift

    pattern="$(echo $pattern | awk -F'/' '{print $2}')"

    [ "$DRYRUN" != "yes" ] && {
        fix_pattern "/${pattern}/d" "$ifile"
    }
}

fixit () {
    typeset pattern="$1"; shift
    typeset ifile="$1"; shift

    [ "$REMOVE" == "yes" ] && {
        remove_pattern "$pattern" "$ifile"
    } || {
        fix_pattern "$pattern" "$ifile"
    }
}

get_pattern () {
    typeset pattern="$1"; shift
    typeset ifile="$1"; shift

    typeset O=$(egrep --regexp="$pattern" "$ifile" | awk '{print $3}' | tr --delete ';')
    [ "$SILENT" == "yes" ] && return 0
    [ "${O}x" != "x" ] && echo "$O" || return 0
}

main () {
    typeset FILENAME=${1:?usage;exit 1;}

    case "$FILENAME" in
        -h|--help) usage; exit 0;;
    esac

    typeset filedir=$(dirname "$FILENAME")
    typeset ofile="$(mktemp --tmpdir="${filedir}" dhcpd.conf.tmp.XXXXXXX)"

    cp "$FILENAME" "$ofile"

    get_pattern "\s(..:){4}..;" "$ofile"
    fixit 's/ethernet (..:..:..:..:..);/ethernet 00:\1;/' "$ofile"

    get_pattern "\s(..:){6}..;" "$ofile"
    fixit 's/\s..:((..:){5}..);/\s\1/' "$ofile"

    get_pattern "ethernet ..:..:..:..:.:..;" "$ofile"
    fixit 's/ethernet (..:..:..:..):(.):(..;)/ethernet \1:0\2:\3/' "$ofile"

    get_pattern "ethernet ..:..:..:..:..:.;" "$ofile"
    fixit 's/ethernet (..:..:..:..:..):(.;)/ethernet \1:0\2/' "$ofile"

    get_pattern "ethernet ..:..:.:..:..:..;" "$ofile"
    fixit 's/ethernet (..:..):(.):(..:..:..;)/ethernet \1:0\2:\3/' "$ofile"

    get_pattern "ethernet ..:.:..:..:..:..;" "$ofile"
    fixit 's/ethernet (..):(.):(..:..:..:..;)/ethernet \1:0\2:\3/' "$ofile"

    get_pattern "ethernet .:..:..:..:..:..;" "$ofile"
    fixit 's/ethernet (.:..:..:..:..:..;)/ethernet 0\1/' "$ofile"

    get_pattern "(subnet.*[0-9]){" "$ofile"
    fix_pattern 's/(subnet.*[0-9])\{/\1 \{/' "$ofile" # Make sure we don't delete the line

    typeset OUTPUT="/dev/stdout"
    [ "$OVERWRITE" == "yes" ] && OUTPUT="$FILENAME"
    cat "$ofile" > "$OUTPUT" && rm "$ofile"
}

main $*
