#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o noglob
set -o pipefail

TODO="Use Nexus' Lucene search index to first retrieve artifact data so 
user could omit version and packaging"

TRACE=${TRACE:-no}
[ "$TRACE" != "no" ] && set -o xtrace

THIS=$(which $0)
THISNAME=$(basename "$THIS")
JQ="/bin/jq"

ARTIFACT_REGEX="(([A-Za-z_-]+:){2}(([0-9]+.?){2}([0-9]+)?|LATEST)(-(SNAPSHOT|RC[0-9]+))?(:?(war|jar|pom))?,?)+"
NEXUS_BASE=${NEXUS_BASE:-"http://nexus"}
NEXUS_WS=${NEXUS_WS:-"service/local"}
VERBOSITY=${VERBOSITY:-no}
TARGET_DIR=${TARGET_DIR:-"/tmp"}
REPOSITORY_OVERRIDE=${REPOSITORY_OVERRIDE:-"x"}

ENV_VARS="NEXUS_BASE NEXUS_WS REPOSITORY_OVERRIDE TARGET_DIR TRACE VERBOSITY"

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
	Download an artifact hosted on a Nexus repository.

	Usage:
	${THISNAME} <artifact> [-h|-e]

	<artifact> Long name of the artifact you want to deploy.
	Format is groupId:artifactId:version:packaging

	Options:
	-h --help	Display this help
	-e --env	Display current environment variables

	Environment:
	NEXUS_BASE		Nexus repository base url
	NEXUS_WS		Nexus webservice relative path
	REPOSITORY_OVERRIDE	Force used repository
	TARGET_DIR		Download into given folder
	TRACE			set -o xtrace
	VERBOSITY		Use DEBUG for full log

	Notes:
	* LATEST is supported but will assume you want a SNAPSHOT
	* /!\ with LATEST which is maven-dependent and relies on the
	maven-metadata.xml file 
	* Packaging is optionnal and is assume to be "jar" if not set
	* curl --continue-at is not supported by Nexus (as of v2.11.4-01)
	* To fetch the artifact from Nexus curl is used with the 
	following arguments: 
	--fail --silent --netrc -XGET
	--netrc means that the \$HOME/.netrc file must be present
	
	TODO:
	${TODO}

	Usage examples:
	${THISNAME} group:arti1:LATEST
	${THISNAME} group:arti2:0.0.1-RC1
	EOU
}

fetch_artifact () {
# Retrieve artifact from Nexus webservice into $TARGET_DIR
# Return is the code from curl --fail
	
	typeset repository="$1"; shift
	typeset groupdId="$1"; shift
	typeset artifactId="$1"; shift
	typeset version="$1"; shift
	typeset packaging="$1"; shift

	_info "Fetching: ${groupId}:${artifactId}:${version}:${packaging}"	

	typeset search_string="r=${repository}&g=${groupId}&a=${artifactId}"
	search_string="${search_string}&v=${version}&p=${packaging}"

	typeset local_file="${TARGET_DIR}/${artifactId}-${version}.${packaging}"
	_debug "Local file: ${local_file}"

	typeset fetch_url="${NEXUS_BASE}/${NEXUS_WS}/artifact/maven/content"
	fetch_url="${fetch_url}?${search_string}" 
	_debug "Fetch url: ${fetch_url}"

	curl -XGET \
		--fail \
		--silent \
		--netrc \
		-o "$local_file" \
		"$fetch_url"
}

resolve_latest_version () {
# Retrieve latest version of artifact as resolved by Nexus
# Display version on success, "x" on failure

	typeset repo="$1"; shift
	typeset groupId="$1"; shift
	typeset artifactId="$1"; shift

	typeset search_string="r=${repo}&g=${groupId}&a=${artifactId}"
	search_string="${search_string}&v=LATEST&p=${packaging}"
	
	typeset fetch_url="${NEXUS_BASE}/${NEXUS_WS}/artifact/maven/resolve"
	fetch_url="${fetch_url}?${search_string}"

	typeset version=$(curl -XGET \
		--fail \
		--silent \
		--netrc \
		--header 'Accept: application/json' \
		"${fetch_url}" | \
		"$JQ" -Merc '.data.version')

	[ "${version}x" == "x" ] && echo "x" || echo $version
}

check_artifact_format () {
# Check that given artifact string respects $ARTIFACT_REGEX format
# Return is the code from grep -q 

	typeset artifact="$1"
	echo "$artifact" | grep --quiet --extended-regexp "$ARTIFACT_REGEX"
}

guess_repository () {
# Guess which repository to search into given the
# version string extracted from CLI args

	typeset version="$1"
	typeset repository="releases"

	[ "$(echo ${version} | cut -d'-' -f2)" == "SNAPSHOT" ] && {
		repository="snapshots"
	}

	[ "${REPOSITORY_OVERRIDE}" != "x" ] && \
		repository="$REPOSITORY_OVERRIDE"
	
	echo $repository
}

main () {
	check_environment

	# Check number of args
	[ "$#" -lt 1 ] && {
		usage "Missing argument"
		exit 1
	}

	# CLI avail args
	case "$1" in
		-h|--help)	usage; exit 0;;
		-e|--env)	show_environment; exit 0;;
	esac

	# Check argument format
	typeset gavp="$1"; shift
	check_artifact_format "$gavp" || {
		usage "${gavp} not correctly formatted"
		exit 1
	}

	# Split long name
	IFS=':' read groupId artifactId version packaging <<-EOA
		$gavp
	EOA

	# Guess packaging
	[ "${packaging}x" == "x" ] && packaging="jar"
	 _debug "Packaging: jar"

	_info "Task: ${groupId}:${artifactId}:${version}:${packaging}"

	# Guess used repository
	typeset repository="$(guess_repository "$version")"
	_debug "Repository: ${repository}"

	# Get latest version if needed
	[ "$version" == "LATEST" ] && {
		version="$(resolve_latest_version "$repository" "$groupId" \
			"$artifactId" )"
		[ "${version}" == "x" ] && \
			_critical "Cannot resolve latest version"
		_debug "Latest version is ${version}"
	}

	# Download
	fetch_artifact "$repository" "$groupId" "$artifactId" "$version" \
		"$packaging" || {
		_critical "Unable to fetch artifact (errcode=${?})"
	}
	_info "Done: ${TARGET_DIR}/${artifactId}-${version}.${packaging}"

	exit 0
}

main $@
