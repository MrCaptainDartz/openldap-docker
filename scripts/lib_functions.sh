#!/bin/bash

########################
# Check if the provided argument is an integer
# Arguments:
#   $1 - Value to check
# Returns:
#   Boolean
#########################
is_int() {
    local -r int="${1:?missing value}"
    if [[ "$int" =~ ^-?[0-9]+ ]]; then
        true
    else
        false
    fi
}

########################
# Check if the provided argument is a positive integer
# Arguments:
#   $1 - Value to check
# Returns:
#   Boolean
#########################
is_positive_int() {
    local -r int="${1:?missing value}"
    if is_int "$int" && (( "${int}" >= 0 )); then
        true
    else
        false
    fi
}

########################
# Check if the provided argument is a boolean or is the string 'yes/true'
# Arguments:
#   $1 - Value to check
# Returns:
#   Boolean
#########################
is_boolean_yes() {
    local -r bool="${1:-}"
    # comparison is performed without regard to the case of alphabetic characters
    shopt -s nocasematch
    if [[ "$bool" = 1 || "$bool" =~ ^(yes|true)$ ]]; then
        true
    else
        false
    fi
}

########################
# Check if the provided argument is a boolean yes/no value
# Arguments:
#   $1 - Value to check
# Returns:
#   Boolean
#########################
is_yes_no_value() {
    local -r bool="${1:-}"
    if [[ "$bool" =~ ^(yes|no)$ ]]; then
        true
    else
        false
    fi
}

########################
# Check if the script is currently running as root
# Arguments:
#   $1 - user
#   $2 - group
# Returns:
#   Boolean
#########################
am_i_root() {
    if [[ "$(id -u)" = "0" ]]; then
        true
    else
        false
    fi
}

########################
# Checks whether a directory is empty or not
# arguments:
#   $1 - directory
# returns:
#   boolean
#########################
is_dir_empty() {
    local -r path="${1:?missing directory}"
    # Calculate real path in order to avoid issues with symlinks
    local -r dir="$(realpath "$path")"
    if [[ ! -e "$dir" ]] || [[ -z "$(ls -A "$dir")" ]]; then
        true
    else
        false
    fi
}

########################
# Replace a regex-matching string in a file
# Arguments:
#   $1 - filename
#   $2 - match regex
#   $3 - substitute regex
#   $4 - use POSIX regex. Default: true
# Returns:
#   None
#########################
replace_in_file() {
    local filename="${1:?filename is required}"
    local match_regex="${2:?match regex is required}"
    local substitute_regex="${3:?substitute regex is required}"
    local posix_regex=${4:-true}

    local result

    # We should avoid using 'sed in-place' substitutions
    # 1) They are not compatible with files mounted from ConfigMap(s)
    # 2) We found incompatibility issues with Debian10 and "in-place" substitutions
    local -r del=$'\001' # Use a non-printable character as a 'sed' delimiter to avoid issues
    if [[ $posix_regex = true ]]; then
        result="$(sed -E "s${del}${match_regex}${del}${substitute_regex}${del}g" "$filename")"
    else
        result="$(sed "s${del}${match_regex}${del}${substitute_regex}${del}g" "$filename")"
    fi
    echo "$result" > "$filename"
}

########################
# Read the provided pid file and returns a PID
# Arguments:
#   $1 - Pid file
# Returns:
#   PID
#########################
get_pid_from_file() {
    local pid_file="${1:?pid file is missing}"

    if [[ -f "$pid_file" ]]; then
        if [[ -n "$(< "$pid_file")" ]] && [[ "$(< "$pid_file")" -gt 0 ]]; then
            echo "$(< "$pid_file")"
        fi
    fi
}

########################
# Retries a command a given number of times
# Arguments:
#   $1 - cmd (as a string)
#   $2 - max retries. Default: 12
#   $3 - sleep between retries (in seconds). Default: 5
# Returns:
#   Boolean
#########################
retry_while() {
    local cmd="${1:?cmd is missing}"
    local retries="${2:-12}"
    local sleep_time="${3:-5}"
    local return_value=1

    read -r -a command <<<"$cmd"
    for ((i = 1; i <= retries; i += 1)); do
        "${command[@]}" && return_value=0 && break
        sleep "$sleep_time"
    done
    return $return_value
}

########################
# Stop a service by sending a termination signal to its pid
# Arguments:
#   $1 - Pid file
#   $2 - Signal number (optional)
# Returns:
#   None
#########################
stop_service_using_pid() {
    local pid_file="${1:?pid file is missing}"
    local signal="${2:-}"
    local pid

    pid="$(get_pid_from_file "$pid_file")"
    [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null && return

    if [[ -n "$signal" ]]; then
        kill "-${signal}" "$pid"
    else
        kill "$pid"
    fi

    local counter=10
    while [[ "$counter" -ne 0 ]] && kill -0 "$pid" 2>/dev/null; do
        sleep 1
        counter=$((counter - 1))
    done
}

