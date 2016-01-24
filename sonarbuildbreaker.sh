#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o noglob
set -o pipefail

TRACE=${TRACE:-no}
[ "$TRACE" != "no" ] && set -o xtrace

THIS=$(which $0)
THISNAME=$(basename "$THIS")
JQ="/bin/jq"

MAX_TRY=${MAX_TRY:-10}
SLEEP_FOR=${SLEEP_FOR:-3}
STATUS=FAIL
VERBOSITY=${VERBOSITY:-no}

ENV_VARS="MAX_TRY SLEEP_FOR TRACE VERBOSITY"

_message () {
	typeset timestamp="$(date +'%Y-%m-%d %H:%M:%S')"
	typeset level="$1"; shift
	printf "[%s][%s]\t%s\n" "$timestamp" "$level" "$@" 
}

_debug () { [ "$VERBOSITY" == "DEBUG" ] && _message "DEBUG" "$@" || return 0; }
_info () { _message "INFO" "$@"; }
_warning () { _message "WARNING" "$@" >&2; }
_error () { _message "ERROR" "$@" >&2; }
_critical () { _message "CRITICAL" "$@" >&2; exit 1; }

check_environment () {
	JQ="$(which jq)"
	[ -z "$JQ" ] && _critical "Missing requirement: jq"
	[ -z "$(which curl)" ] && _critical "Missing requirement: curl"

	return 0
}

show_environment () {
# List and display value of environment variables listed in ENV_VARS

	for var in $ENV_VARS; do
		printf "%-20s\t%-20s\n" "$var" "$(eval echo \$$var)"
	done
}

usage () {
	typeset err=${@:-no}	
	[ "$err" != "no" ] && _error "$@"

	cat <<-EOU
	Check a Sonar Project's Quality Gate status and change script's
	exit code accordingly
	See http://docs.sonarqube.org/display/SONAR/Breaking+the+CI+Build

	Usage:
	${THISNAME} <report path> [-h|-e]

	<report path> The path to the report-task.txt file generated
	by a Sonar analysis within the work dir (usually .sonar)

	Options:
	-h --help	Display this help
	-e --env	Display current environment variables

	Environment:
	MAX_TRY		Number of attempts
	SLEEP_FOR	Sleep x seconds between attempts
	TRACE		set -o xtrace
	VERBOSITY	Use DEBUG for full logging
	EOU
}

main () {
	check_environment

	# Check args
	[ "$#" -lt 1 ] && {
		usage "Missing argument"
		exit 1
	}

	case "$1" in
		-h|--help)	usage; exit 0;;
		-e|--env)	show_environment; exit 0;;
	esac

	# Check report exists
	typeset reportpath="$1"; shift
	[ -f "$reportpath" ] || {
		_critical "${reportpath} not found"
	}
	_debug "Report path: ${reportpath}"

	# Load report file
	source "$reportpath"
	_info "Report's task Url: ${ceTaskUrl}"
	_info "Report's server Url: ${serverUrl}"

	# Main loop 
	# See: http://docs.sonarqube.org/display/SONAR/Breaking+the+CI+Build
	for i in $(seq 1 $MAX_TRY); do
		typeset taskresponse=$(curl -s "$ceTaskUrl")
		typeset taskstatus=$(echo "$taskresponse" | \
			"$JQ" -Merc '.task.status')

		_debug "#${i} -> ${taskstatus}"

		[ "$taskstatus" == "SUCCESS" ] && {
			_info "Status SUCCESS"

			typeset analysisid=$(echo "$taskresponse" | \
				"$JQ" -Merc '.task.analysisId')

			typeset gateurl="${serverUrl}/api/qualitygates/project_status"
			gateurl="${gateurl}?analysisId=${analysisid}"
			typeset gatestatus=$(curl -s "$gateurl"| \
				"$JQ" -Merc '.projectStatus.status')

			_info "Gate is ${gatestatus}"
			[ "$gatestatus" == "OK" ] && exit 0 || exit 1
		}

		sleep $SLEEP_FOR
	done
	_error "Analysis took too long"
	exit 1
}

main $@
