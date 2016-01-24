#!/bin/bash

fb5upload () {
	local PASSWORD=${FREEBOX_FTP_PASSWORD:=123456}
	local FILEPATH="$1"
	local TARGET_DIR="$2"; TARGET_DIR=${TARGET_DIR:="/Disque\\ dur/Video"}
	local OUTPUT=/dev/stdout
	local VERBOSE=${VERBOSE:=0}
	local FTP_ADDR=${FREEBOX_FTP_ADDR:="hd1.freebox.fr"}

	# Check file argument
	[ $# -lt 1 ] && {
		cat <<-EOF
		Missing argument
		Usage:
		$FUNCNAME <file>
		
		<file> Path to the file to upload

		Environment:
		PASSWORD	FTP Password
		TARGET_DIR	Remote path
		VERBOSE		0 or 1
		FTP_ADDR	Freebox url
		EOF
		return 1
	}

	# Check file exists
	[ ! -e "${FILEPATH}" ] && {
		echo "File not found ${FILEPATH}" >&2
		return 1
	}

	# Display ftp output or not
	[ $VERBOSE -eq 0 ] && {
		echo "${FILEPATH} -->  ftp://${FTP_ADDR}${TARGET_DIR}"
	} || {
		OUTPUT=/dev/null
	}

	# FTP commands
	ftp -n $FTP_ADDR 1>"${OUTPUT}" <<-THE_END
		quote USER freebox
		quote PASS $PASSWORD

		binary
		cd $TARGET_DIR
		lcd $(dirname $FILEPATH)
		put $(basename $FILEPATH)
		quit
	THE_END

	[ $? -ne 0 ] && echo "Transfert failed" >&2 && return 1
	return 0
	
}
export -f fb5upload
