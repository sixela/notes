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

ARTIFACT_REGEX="(([A-Za-z_-]+:){2}(([0-9]+.?){2}([0-9]+)?|LATEST|RELEASE)(-(SNAPSHOT|RC[0-9]+))?(:?(war|jar|pom))?,?)+"
NEXUS_BASE=${NEXUS_BASE:-"http://nexus"}
NEXUS_WS=${NEXUS_WS:-"service/local"}
VERBOSITY=${VERBOSITY:-INFO}
TARGET_DIR=${TARGET_DIR:-"/tmp"}
PACKAGING_AUTOGUESS=${PACKAGING_AUTOGUESS:-yes}
REPOSITORY_OVERRIDE=${REPOSITORY_OVERRIDE:-"x"}

_CACHED_QUERY="x"

ENV_VARS="NEXUS_BASE NEXUS_WS PACKAGING_AUTOGUESS REPOSITORY_OVERRIDE \
TARGET_DIR TRACE VERBOSITY"

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
	[ -z "$JQ" ] && _critical "Requirement jq is missing"
	[ -z "$(which curl)" ] && _critical "Requirement curl is missing"

	return 0
}

show_environment () {
# List and display value of environment variables listed in ENV_VARS

	for var in $ENV_VARS; do
		printf "%-20s\t%-20s\n" "$var" "$(eval echo \$$var)"
	done
}

usage () {
# Parameters: 
#	@Optionnal err
#
# Display usage message and error message if such message is provided

	typeset err=${@:-no}
	[ "$err" != "no" ] && _error "$@"

	cat <<-EOU
	Download an artifact hosted on a Nexus repository.

	Usage:
	${THISNAME} [-gprv] <artifact> [-h|-e]

	<artifact> Long name of the artifact you want to deploy.
	Format is groupId:artifactId:version:packaging

	Options:
	-h --help	Display this help
	-e --env	Display current environment variables

	-g --gavp	Display full coordinates only (format g:a:v:p)
	-p --packaging	Display packaging only
	-r --repository	Display repository only
	-v --version	Display version only

	Environment:
	NEXUS_BASE		Nexus repository base url
	NEXUS_WS		Nexus webservice relative path
	PACKAGING_AUTOGUESS	Automatically choose packaging if not provided
	REPOSITORY_OVERRIDE	Force used repository
	TARGET_DIR		Download into given folder
	TRACE			set -o xtrace
	VERBOSITY		Use DEBUG for full log

	Notes:
	* LATEST is supported but will assume you want a SNAPSHOT
	* /!\ with LATEST which is maven-dependent and relies on the
	maven-metadata.xml file 
	* curl --continue-at is not supported by Nexus (as of v2.11.4-01)
	* To fetch the artifact from Nexus curl is used with the 
	following arguments: 
	--fail --silent --netrc -XGET
	--netrc means that the \$HOME/.netrc file must be present
	
	Usage examples:
	${THISNAME} group:arti1:LATEST 	# Get latest snapshot
	${THISNAME} group:arti2:0.0.1-RC1:war # Get 0.0.1-RC1 war file
	${THISNAME} -v group:arti2:RELEASE	# Get version of last release
	EOU
}

fetch_artifact () {
# Parameters:
# 	repositoryId
#	groupId
#	artifactId
#	version
#	packaging
# Return:
#	Code from curl --fail
#
# Retrieve artifact from Nexus webservice into $TARGET_DIR
	
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
# Parameters:
# 	repo
#	groupId
#	artifactId
# Return:
#	echo retrieved version or "x"
#
# Retrieve latest version of artifact as resolved by Nexus

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
# Parameters:
#	artifact
# Return:
#	Return code from grep --quiet
#
# Check that given artifact string respects $ARTIFACT_REGEX format

	typeset artifact="$1"
	echo "$artifact" | grep --quiet --extended-regexp "$ARTIFACT_REGEX"
}

guess_search () {
# Parameters:
#	groupId
#	artifactId
# Return:
#	Result from Nexus search WS (json)
#
# Search all data related to groupId and artifactId
# Cache the result into _CACHED_QUERY

	typeset groupId="$1"; shift
	typeset artifactId="$1"; shift

	typeset search_url="${NEXUS_BASE}/${NEXUS_WS}/lucene/search"
	search_url="${search_url}?g=${groupId}&a=${artifactId}"

	[ "${_CACHED_QUERY}" == "x" ] && {

		_CACHED_QUERY=$(curl -XGET \
                	--fail \
                	--silent \
                	--netrc \
                	--header 'Accept: application/json' \
                	"$search_url")
	} 

	echo "$_CACHED_QUERY"
}

guess_repository () {
# Parameters:
#	groupId
#	artifactId
#	version
# Return:
#	echo found repository or "x"
#
# Given results from guess_search select first element in
# the list with the relevant repositoryPolicy (RELEASE or
# SNAPSHOT

	typeset groupId="$1"; shift
	typeset artifactId="$1"; shift
	typeset version="$1"; shift


	typeset search_for="x"
	case "$version" in
		*SNAPSHOT|LATEST) 	search_for="SNAPSHOT" ;;
		*)		search_for="RELEASE" ;;
	esac

	typeset repository=$(guess_search "$groupId" "$artifactId" | \
		"$JQ" -Merc --arg POLICY "$search_for" \
		'[.repoDetails[] | select(.repositoryPolicy==$POLICY)][0].repositoryId')

	[ "${REPOSITORY_OVERRIDE}" != "x" ] && \
		repository="$REPOSITORY_OVERRIDE"
	
	[ "$packaging" == "null" ] && echo "x" ||  echo $repository
}

guess_packaging () {
# Parameters:
#	groupId
#	artifactId
# Return:
#	echo found packaging or "x"
#
# Given the results from guess_search return packaging
# or fail or use first one in alphanum order (eg. jar > pom > war) depending
# on PACKAGING_AUTOGUESS value

	typeset groupId="$1"; shift
	typeset artifactId="$1"; shift

	typeset packaging=$(guess_search "$groupId" "$artifactId" | \
		"$JQ" -Merc \
		'.data[0].artifactHits[0].artifactLinks')

	# Check we got only 1 result
	typeset length=$(echo "$packaging" | "$JQ" -Merc '. | length')
	[ "$length" -eq 1 ] && { # Ok, we know the packaging
		packaging=$(echo "$packaging" | "$JQ" -Merc '.[0].extension')
	# Multiple results, fail or pick first element (alpanum order)
	# Depending on PACKAGING_AUTOGUESS
	} || {
		[ "$PACKAGING_AUTOGUESS" != "yes" ] && {
			packaging="null"
		} || {
			packaging=$(echo "$packaging" | "$JQ" -Merc \
			'[.[] | select(.extension) | .extension] |sort | .[0]')
		}
	}

	[ "${packaging}" == "null" ] && echo "x" || echo $packaging
}

main () {
	check_environment

	# Check number of args
	[ "$#" -lt 1 ] && {
		usage "Missing argument"
		exit 1
	}

	# CLI avail args
	typeset action="download"
	case "$1" in
		-h|--help)	usage; exit 0;;
		-e|--env)	show_environment; exit 0;;
		-g|--gavp)	action="gavp";;
		-p|--packaging)	action="packaging";;
		-r|--repository)action="repository";;
		-v|--version)	action="version";;
	esac
	[ "$#" -ge 2 ] && shift # Remove action from args

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
	[ "${packaging}x" == "x" ] && {
		_debug "Guess packaging"
		packaging="$(guess_packaging $groupId $artifactId)"
		[ "${packaging}" == "x" ] && {
			_warning "Failed guessing packaging. Fallback: jar"
			packaging="jar"
		}
	}
	_debug "Packaging: ${packaging}"
	[ "$action" == "packaging" ] && {
		echo "$packaging"
		exit 0
	}

	# Guess repository
	_debug "Guess repository"
	typeset repository=$(guess_repository "$groupId" "$artifactId" "$version")
	_debug "Repository: ${repository}"
	[ "$action" == "repository" ] && {
		echo "$repository"
		exit 0
	}

	# Get latest version if needed
	_debug "Guess version"
	case "$version" in
		LATEST|RELEASE)
			version="$(resolve_latest_version "$repository" \
			"$groupId" "$artifactId" )"

			[ "${version}" == "x" ] && \
				_critical "Cannot resolve latest version"
			_debug "Latest version: ${version}"
		;;
	esac
	[ "$action" == "version" ] && {
		echo "$version"
		exit 0
	}

	# Display coordinates
	[ "$action" == "gavp" ] && {
		echo "${groupId}:${artifactId}:${version}:${packaging}"
		exit 0
	}

	# Download
	_info "Task: ${groupId}:${artifactId}:${version}:${packaging}"
	fetch_artifact "$repository" "$groupId" "$artifactId" "$version" \
		"$packaging" || {
		_critical "Unable to fetch artifact (errcode=${?})"
	}
	_info "Done: ${TARGET_DIR}/${artifactId}-${version}.${packaging}"

	exit 0
}

main $@
