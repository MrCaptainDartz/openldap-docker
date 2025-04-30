#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

#Import Libraries
. /opt/scripts/lib_functions.sh
. /opt/scripts/lib_openldap.sh

#####
# Set Environment Variables
#####

# Paths
export LDAP_BASE_DIR="/opt/openldap"
export LDAP_BIN_DIR="${LDAP_BASE_DIR}/bin"
export LDAP_SBIN_DIR="${LDAP_BASE_DIR}/sbin"
export LDAP_CONF_DIR="${LDAP_BASE_DIR}/etc/openldap"
export LDAP_SHARE_DIR="${LDAP_BASE_DIR}/share"
export LDAP_VAR_DIR="${LDAP_BASE_DIR}/var"
export LDAP_LIBEXEC_DIR="${LDAP_BASE_DIR}/libexec"
export LDAP_VOLUME_DIR="/openldap"
export LDAP_DATA_DIR="${LDAP_VOLUME_DIR}/data"
export LDAP_ACCESSLOG_DATA_DIR="${LDAP_DATA_DIR}/accesslog"
export LDAP_ONLINE_CONF_DIR="${LDAP_VOLUME_DIR}/slapd.d"
export LDAP_PID_FILE="${LDAP_VAR_DIR}/run/slapd.pid"
export LDAP_CUSTOM_LDIF_DIR="${LDAP_CUSTOM_LDIF_DIR:-/ldifs}"
export LDAP_CUSTOM_SCHEMA_FILE="${LDAP_CUSTOM_SCHEMA_FILE:-/schema/custom.ldif}"
export LDAP_CUSTOM_SCHEMA_DIR="${LDAP_CUSTOM_SCHEMA_DIR:-/schemas}"
export LDAP_TLS_CERT_FILE="${LDAP_TLS_CERT_FILE:-}"
export LDAP_TLS_KEY_FILE="${LDAP_TLS_KEY_FILE:-}"
export LDAP_TLS_CA_FILE="${LDAP_TLS_CA_FILE:-}"
export LDAP_TLS_VERIFY_CLIENTS="${LDAP_TLS_VERIFY_CLIENTS:-never}"
export LDAP_TLS_DH_PARAMS_FILE="${LDAP_TLS_DH_PARAMS_FILE:-}"
# Users
export LDAP_DAEMON_USER="slapd"
export LDAP_DAEMON_GROUP="slapd"
# Settings
export LDAP_PORT_NUMBER="${LDAP_PORT_NUMBER:-1389}"
export LDAP_LDAPS_PORT_NUMBER="${LDAP_LDAPS_PORT_NUMBER:-1636}"
export LDAP_ENABLE_PROXYPROTO="${LDAP_ENABLE_PROXYPROTO:-no}"
export LDAP_PROXYPROTO_PORT_NUMBER="${LDAP_PROXYPROTO_PORT_NUMBER:-"${LDAP_PORT_NUMBER}"}"
export LDAP_PROXYPROTO_LDAPS_PORT_NUMBER="${LDAP_PROXYPROTO_LDAPS_PORT_NUMBER:-"${LDAP_LDAPS_PORT_NUMBER}"}"
export LDAP_ROOT="${LDAP_ROOT:-dc=example,dc=org}"
export LDAP_SUFFIX="$(if [ -z "${LDAP_SUFFIX+x}" ]; then echo "${LDAP_ROOT}"; else echo "${LDAP_SUFFIX}"; fi)"
export LDAP_ADMIN_USERNAME="${LDAP_ADMIN_USERNAME:-admin}"
export LDAP_ADMIN_DN="${LDAP_ADMIN_USERNAME/#/cn=},${LDAP_ROOT}"
export LDAP_ADMIN_PASSWORD="${LDAP_ADMIN_PASSWORD:-adminpassword}"
export LDAP_CONFIG_ADMIN_ENABLED="${LDAP_CONFIG_ADMIN_ENABLED:-no}"
export LDAP_CONFIG_ADMIN_USERNAME="${LDAP_CONFIG_ADMIN_USERNAME:-admin}"
export LDAP_CONFIG_ADMIN_DN="${LDAP_CONFIG_ADMIN_USERNAME/#/cn=},cn=config"
export LDAP_CONFIG_ADMIN_PASSWORD="${LDAP_CONFIG_ADMIN_PASSWORD:-configpassword}"
export LDAP_ADD_SCHEMAS="${LDAP_ADD_SCHEMAS:-yes}"
export LDAP_EXTRA_SCHEMAS="${LDAP_EXTRA_SCHEMAS:-cosine,inetorgperson,nis}"
export LDAP_SKIP_DEFAULT_TREE="${LDAP_SKIP_DEFAULT_TREE:-no}"
export LDAP_USERS="${LDAP_USERS:-user01,user02}"
export LDAP_PASSWORDS="${LDAP_PASSWORDS:-user01,user02}"
export LDAP_USER_DC="${LDAP_USER_DC:-}"
export LDAP_USER_OU="${LDAP_USER_OU:-${LDAP_USER_DC:-users}}"
export LDAP_GROUP_OU="${LDAP_GROUP_OU:-${LDAP_USER_DC:-groups}}"
export LDAP_GROUP="${LDAP_GROUP:-readers}"
export LDAP_ENABLE_TLS="${LDAP_ENABLE_TLS:-no}"
export LDAP_REQUIRE_TLS="${LDAP_REQUIRE_TLS:-no}"
export LDAP_ULIMIT_NOFILES="${LDAP_ULIMIT_NOFILES:-1024}"
export LDAP_ALLOW_ANON_BINDING="${LDAP_ALLOW_ANON_BINDING:-yes}"
export LDAP_LOGLEVEL="${LDAP_LOGLEVEL:-256}"
export LDAP_PASSWORD_HASH="${LDAP_PASSWORD_HASH:-{SSHA\}}"
export LDAP_CONFIGURE_PPOLICY="${LDAP_CONFIGURE_PPOLICY:-no}"
export LDAP_PPOLICY_USE_LOCKOUT="${LDAP_PPOLICY_USE_LOCKOUT:-no}"
export LDAP_PPOLICY_HASH_CLEARTEXT="${LDAP_PPOLICY_HASH_CLEARTEXT:-no}"
export LDAP_ENABLE_ACCESSLOG="${LDAP_ENABLE_ACCESSLOG:-no}"
export LDAP_ACCESSLOG_DB="${LDAP_ACCESSLOG_DB:-cn=accesslog}"
export LDAP_ACCESSLOG_LOGOPS="${LDAP_ACCESSLOG_LOGOPS:-writes}"
export LDAP_ACCESSLOG_LOGSUCCESS="${LDAP_ACCESSLOG_LOGSUCCESS:-TRUE}"
export LDAP_ACCESSLOG_LOGPURGE="${LDAP_ACCESSLOG_LOGPURGE:-07+00:00 01+00:00}"
export LDAP_ACCESSLOG_LOGOLD="${LDAP_ACCESSLOG_LOGOLD:-(objectClass=*)}"
export LDAP_ACCESSLOG_LOGOLDATTR="${LDAP_ACCESSLOG_LOGOLDATTR:-objectClass}"
export LDAP_ACCESSLOG_ADMIN_USERNAME="${LDAP_ACCESSLOG_ADMIN_USERNAME:-admin}"
export LDAP_ACCESSLOG_ADMIN_DN="${LDAP_ACCESSLOG_ADMIN_USERNAME/#/cn=},${LDAP_ACCESSLOG_DB:-cn=accesslog}"
export LDAP_ACCESSLOG_ADMIN_PASSWORD="${LDAP_ACCESSLOG_PASSWORD:-accesspassword}"
export LDAP_ENABLE_SYNCPROV="${LDAP_ENABLE_SYNCPROV:-no}"
export LDAP_SYNCPROV_CHECKPPOINT="${LDAP_SYNCPROV_CHECKPPOINT:-100 10}"
export LDAP_SYNCPROV_SESSIONLOG="${LDAP_SYNCPROV_SESSIONLOG:-100}"

# By setting an environment variable matching *_FILE to a file path, the prefixed environment
# variable will be overridden with the value specified in that file
ldap_env_vars=(
    LDAP_ADMIN_PASSWORD
    LDAP_CONFIG_ADMIN_PASSWORD
    LDAP_ACCESSLOG_ADMIN_PASSWORD
)
for env_var in "${ldap_env_vars[@]}"; do
    file_env_var="${env_var}_FILE"
    if [[ -n "${!file_env_var:-}" ]]; then
        if [[ -r "${!file_env_var:-}" ]]; then
            export "${env_var}=$(< "${!file_env_var}")"
            unset "${file_env_var}"
        else
            warn "Skipping export of '${env_var}'. '${!file_env_var:-}' is not readable."
        fi
    fi
done
unset ldap_env_vars

# Setting encrypted admin passwords
export LDAP_ENCRYPTED_ADMIN_PASSWORD="$(echo -n $LDAP_ADMIN_PASSWORD | slappasswd -n -T /dev/stdin)"
export LDAP_ENCRYPTED_CONFIG_ADMIN_PASSWORD="$(echo -n $LDAP_CONFIG_ADMIN_PASSWORD | slappasswd -n -T /dev/stdin)"
export LDAP_ENCRYPTED_ACCESSLOG_ADMIN_PASSWORD="$(echo -n $LDAP_ACCESSLOG_ADMIN_PASSWORD | slappasswd -n -T /dev/stdin)"

#####
# Validate environment variables
#####

for var in LDAP_SKIP_DEFAULT_TREE LDAP_ENABLE_TLS LDAP_ENABLE_PROXYPROTO; do
    if ! is_yes_no_value "${!var}"; then
        echo "The allowed values for $var are: yes or no" >&2; exit 1
    fi
done

if is_boolean_yes "$LDAP_ENABLE_TLS"; then
    if [[ -z "$LDAP_TLS_CERT_FILE" ]]; then
        echo "You must provide a X.509 certificate in order to use TLS" >&2; exit 1
    elif [[ ! -f "$LDAP_TLS_CERT_FILE" ]]; then
        echo "The X.509 certificate file in the specified path ${LDAP_TLS_CERT_FILE} does not exist" >&2; exit 1
    fi
    if [[ -z "$LDAP_TLS_KEY_FILE" ]]; then
        echo "You must provide a private key in order to use TLS" >&2; exit 1
    elif [[ ! -f "$LDAP_TLS_KEY_FILE" ]]; then
        echo "The private key file in the specified path ${LDAP_TLS_KEY_FILE} does not exist" >&2; exit 1
    fi
    if [[ -z "$LDAP_TLS_CA_FILE" ]]; then
        echo "You must provide a CA X.509 certificate in order to use TLS" >&2; exit 1
    elif [[ ! -f "$LDAP_TLS_CA_FILE" ]]; then
        echo "The CA X.509 certificate file in the specified path ${LDAP_TLS_CA_FILE} does not exist" >&2; exit 1
    fi
fi

read -r -a users <<< "$(tr ',;' ' ' <<< "${LDAP_USERS}")"
read -r -a passwords <<< "$(tr ',;' ' ' <<< "${LDAP_PASSWORDS}")"
if [[ "${#users[@]}" -ne "${#passwords[@]}" ]]; then
    echo "Specify the same number of passwords on LDAP_PASSWORDS as the number of users on LDAP_USERS!" >&2; exit 1
fi

for var in LDAP_PORT_NUMBER LDAP_LDAPS_PORT_NUMBER LDAP_PROXYPROTO_PORT_NUMBER LDAP_PROXYPROTO_LDAPS_PORT_NUMBER; do
    if ! is_positive_int "${!var}"; then
        echo "The value for $var must be positive integer!" >&2; exit 1
    fi
done

if [[ -n "$LDAP_PORT_NUMBER" ]] && [[ -n "$LDAP_LDAPS_PORT_NUMBER" ]]; then
    if [[ "$LDAP_PORT_NUMBER" -eq "$LDAP_LDAPS_PORT_NUMBER" ]]; then
        echo "LDAP_PORT_NUMBER and LDAP_LDAPS_PORT_NUMBER are bound to the same port!" >&2; exit 1
    fi
fi

if [[ -n "$LDAP_PROXYPROTO_PORT_NUMBER" ]] && [[ -n "$LDAP_PROXYPROTO_LDAPS_PORT_NUMBER" ]]; then
    if [[ "$LDAP_PROXYPROTO_PORT_NUMBER" -eq "$LDAP_PROXYPROTO_LDAPS_PORT_NUMBER" ]]; then
        echo "LDAP_PROXYPROTO_PORT_NUMBER and LDAP_PROXYPROTO_LDAPS_PORT_NUMBER are bound to the same port!" >&2; exit 1
    fi
fi

if [[ -n "$LDAP_USER_DC" ]]; then
    echo "The env variable 'LDAP_USER_DC' has been deprecated and will be removed in a future release. Please use 'LDAP_USER_OU' and 'LDAP_GROUP_OU' instead." >&2
fi


if [[ "$1" = "/opt/scripts/run_openldap.sh" ]]; then
    # Ensure OpenLDAP is stopped when this script ends
    trap "ldap_stop" EXIT
    # Initialize openldap
    ldap_initialize
    # Custom initialization scripts
    ldap_custom_init_scripts
    #Stop OpenLDAP server
    ldap_stop
fi

echo ""
exec "$@"