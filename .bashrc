PATH="${PATH}:~/bin"
PATH="${PATH}:/opt/terraform"

alias cp='cp -v'
alias mv='mv -v'
alias shuf='gshuf'

alias dockstopall='[ $(docker ps -aq | wc -l) -ne 0 ] && docker stop $(docker ps -aq)'
alias dockrmall='[ $(docker ps -aq | wc -l) -ne 0 ] && docker rm $(docker ps -aq)'

alias godev='cd ~/Documents/Github'
alias vlc='/Applications/VLC.app/Contents/MacOS/VLC'
alias lla='ls -al'
alias ll='ls -l'
alias pdfjoin='/System/Library/Automator/Combine\ PDF\ Pages.action/Contents/Resources/join.py'
alias airport='/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport'

alias dupct="du -x -d1|sort -rn|awk -F / -v c=\$COLUMNS 'NR==1{t=\$1} NR>1{r=int(\$1/t*c+.5); b=\"\\033[1;31m\"; for (i=0; i<r; i++) b=b\"#\"; printf \" %5.2f%% %s\\033[0m %s\\n\", \$1/t*100, b, \$2}'"
alias mkpasswd="openssl rand -base64 $1"

export PS1="\[\e[00;37m\]\u@\h[\t]:[\w]>\$?\\$ \[\e[0m\]"

curljson () {
	curl -s "$1" | jq
}
export -f curljson

mkv_to_mp4 () {
	local IN="$1"
	local OUT="$2"

	local FFMPEG=$(which ffmpeg)

	$FFMPEG -i "$IN" -c:v copy -c:a copy "$OUT"
}

to_mp3 () {
	local FILEPATH="$1"
	local OUTFILE=${1%.*}.mp3	

	local FFMPEG=$(which ffmpeg)

	$FFMPEG -i "$FILEPATH" -f mp3 -ab 320k -q:a 1 -map_metadata 0 -id3v2_version 3 "$OUTFILE"	
}
export -f to_mp3

. ./fb5upload.sh
. ./bashrc_ssh
