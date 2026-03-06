#!/bin/bash

. /opt/scripts/lib_functions.sh

########################
# Check if OpenLDAP is running
# Globals:
#   LDAP_PID_FILE
# Arguments:
#   None
# Returns:
#   Whether slapd is running
#########################
is_ldap_running() {
    local pid
    pid="$(get_pid_from_file "${LDAP_PID_FILE}")"
    if [[ -n "${pid}" ]]; then
        kill -0 "${pid}" 2>/dev/null 
    else
        false
    fi
}

########################
# Check if OpenLDAP is not running
# Arguments:
#   None
# Returns:
#   Whether slapd is not running
#########################
is_ldap_not_running() {
    ! is_ldap_running
}

########################
# Start OpenLDAP server in background
# Arguments:
#   $1 - max retries. Default: 12
#   $2 - sleep between retries (in seconds). Default: 1
# Returns:
#   None
#########################
ldap_start_bg() {
    local -r retries="${1:-12}"
    local -r sleep_time="${2:-1}"
    local -a flags=("-h" "ldap://:${LDAP_PORT_NUMBER}/ ldapi:/// " "-F" "${LDAP_CONF_DIR}/slapd.d" "-d" "$LDAP_LOGLEVEL")

    if is_ldap_not_running; then
        echo "Starting OpenLDAP server in background"
        ulimit -n "$LDAP_ULIMIT_NOFILES"
        am_i_root && flags=("-u" "$LDAP_DAEMON_USER" "${flags[@]}")
        slapd "${flags[@]}" &
        if ! retry_while is_ldap_running "$retries" "$sleep_time"; then
            echo "OpenLDAP failed to start" >&2
            return 1
        fi
    fi
}

########################
# Stop OpenLDAP server
# Arguments:
#   $1 - max retries. Default: 12
#   $2 - sleep between retries (in seconds). Default: 1
# Returns:
#   None
#########################
ldap_stop() {
    local -r retries="${1:-12}"
    local -r sleep_time="${2:-1}"

    are_db_files_locked() {
        local return_value=0
        read -r -a db_files <<< "$(find "$LDAP_DATA_DIR" -type f -print0 | xargs -0)"
        for f in "${db_files[@]}"; do
            fuser "$f" && return_value=1
        done
        return "$return_value"
    }

    is_ldap_not_running && return

    stop_service_using_pid "$LDAP_PID_FILE"
    if ! retry_while are_db_files_locked "$retries" "$sleep_time"; then
        echo "OpenLDAP failed to stop" >&2
        return 1
    fi
}
########################
# Create slapd.ldif
# Globals:
#   LDAP_*
# Arguments:
#   None
# Returns:
#   None
#########################
ldap_create_slapd_file() {
    echo "Creating slapd.ldif"
    cat > "${LDAP_SHARE_DIR}/slapd.ldif" << EOF
#
# See slapd-config(5) for details on configuration options.
# This file should NOT be world readable.
#

dn: cn=config
objectClass: olcGlobal
cn: config
olcArgsFile: /opt/openldap/var/run/slapd.args
olcPidFile: /opt/openldap/var/run/slapd.pid

#
# Enable pw-sha2 module
#
dn: cn=module,cn=config
cn: module
objectClass: olcModuleList
olcModulePath: /opt/openldap/libexec/openldap
olcModuleLoad: pw-sha2.so

#
# Schema settings
#

dn: cn=schema,cn=config
objectClass: olcSchemaConfig
cn: schema

include: file:///opt/openldap/etc/openldap/schema/core.ldif

#
# Frontend settings
#

dn: olcDatabase=frontend,cn=config
objectClass: olcDatabaseConfig
objectClass: olcFrontendConfig
olcDatabase: frontend

#
# Configuration database
#

dn: olcDatabase=config,cn=config
objectClass: olcDatabaseConfig
olcDatabase: config
olcAccess: to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage by * none

#
# Server status monitoring
#

dn: olcDatabase=monitor,cn=config
objectClass: olcDatabaseConfig
olcDatabase: monitor
olcAccess: to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read by dn.base="cn=Manager,dc=my-domain,dc=com" read by * none

#
# Backend database definitions
#

dn: olcDatabase=mdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcMdbConfig
olcDatabase: mdb
olcDbMaxSize: 1073741824
olcSuffix: dc=my-domain,dc=com
olcRootDN: cn=Manager,dc=my-domain,dc=com
olcMonitoring: FALSE
olcDbDirectory:	/openldap/data
olcDbIndex: objectClass eq,pres
olcDbIndex: ou,cn,mail,surname,givenname eq,pres,sub
EOF

}

########################
# Create LDAP online configuration
# Globals:
#   LDAP_*
# Arguments:
#   None
# Returns:
#   None
#########################
ldap_create_online_configuration() {
    echo "Creating LDAP online configuration"

    ldap_create_slapd_file
    ! am_i_root && replace_in_file "${LDAP_SHARE_DIR}/slapd.ldif" "uidNumber=0" "uidNumber=$(id -u)"
    local -a flags=(-F "$LDAP_ONLINE_CONF_DIR" -n 0 -l "${LDAP_SHARE_DIR}/slapd.ldif")
    if am_i_root; then
        run_as_user "$LDAP_DAEMON_USER" slapadd "${flags[@]}"
    else
        slapadd "${flags[@]}"
    fi
}

########################
# Configure LDAP credentials for admin user
# Globals:
#   LDAP_*
# Arguments:
#   None
# Returns:
#   None
#########################
ldap_admin_credentials() {
    echo "Configure LDAP credentials for admin user"
    cat > "${LDAP_SHARE_DIR}/admin.ldif" << EOF
dn: olcDatabase={2}mdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: $LDAP_SUFFIX

dn: olcDatabase={2}mdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: $LDAP_ADMIN_DN

dn: olcDatabase={2}mdb,cn=config
changeType: modify
add: olcRootPW
olcRootPW: $LDAP_ENCRYPTED_ADMIN_PASSWORD

dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external, cn=auth" read by dn.base="${LDAP_ADMIN_DN}" read by * none
EOF
    if is_boolean_yes "$LDAP_CONFIG_ADMIN_ENABLED"; then
        cat >> "${LDAP_SHARE_DIR}/admin.ldif" << EOF

dn: olcDatabase={0}config,cn=config
changetype: modify
add: olcRootDN
olcRootDN: $LDAP_CONFIG_ADMIN_DN

dn: olcDatabase={0}config,cn=config
changetype: modify
add: olcRootPW
olcRootPW: $LDAP_ENCRYPTED_CONFIG_ADMIN_PASSWORD
EOF
    fi
    ldapmodify -Y EXTERNAL -H "ldapi:///" -f "${LDAP_SHARE_DIR}/admin.ldif"
}

########################
# Disable LDAP anonymous bindings
# Globals:
#   LDAP_*
# Arguments:
#   None
# Returns:
#   None
#########################
ldap_disable_anon_binding() {
    echo "Disable LDAP anonymous binding"
    cat > "${LDAP_SHARE_DIR}/disable_anon_bind.ldif" << EOF
dn: cn=config
changetype: modify
add: olcDisallows
olcDisallows: bind_anon

dn: cn=config
changetype: modify
add: olcRequires
olcRequires: authc
EOF
    ldapmodify -Y EXTERNAL -H "ldapi:///" -f "${LDAP_SHARE_DIR}/disable_anon_bind.ldif"
}

########################
# Add LDAP schemas
# Globals:
#   LDAP_*
# Arguments:
#   None
# Returns
#   None
#########################
ldap_add_schemas() {
    echo "Adding LDAP extra schemas"
    read -r -a schemas <<< "$(tr ',;' ' ' <<< "${LDAP_EXTRA_SCHEMAS}")"
    for schema in "${schemas[@]}"; do
        ldapadd -Y EXTERNAL -H "ldapi:///" -f "${LDAP_CONF_DIR}/schema/${schema}.ldif"
    done
}

########################
# Add custom schema
# Globals:
#   LDAP_*
# Arguments:
#   None
# Returns
#   None
#########################
ldap_add_custom_schema() {
    echo "Adding custom Schema : $LDAP_CUSTOM_SCHEMA_FILE ..."
    slapadd -F "$LDAP_ONLINE_CONF_DIR" -n 0 -l  "$LDAP_CUSTOM_SCHEMA_FILE"
    ldap_stop
     while is_ldap_running; do sleep 1; done
    ldap_start_bg
}

########################
# Add custom schemas
# Globals:
#   LDAP_*
# Arguments:
#   None
# Returns
#   None
#########################
ldap_add_custom_schemas() {
    echo "Adding custom schemas : $LDAP_CUSTOM_SCHEMA_DIR ..."
    find "$LDAP_CUSTOM_SCHEMA_DIR" -maxdepth 1 \( -type f -o -type l \) -iname '*.ldif' -print0 | sort -z | xargs --null -I{} bash -c "slapadd -F \"$LDAP_ONLINE_CONF_DIR\" -n 0 -l {}"
    ldap_stop
    while is_ldap_running; do sleep 1; done
    ldap_start_bg
}

########################
# Create LDAP tree
# Globals:
#   LDAP_*
# Arguments:
#   None
# Returns:
#   None
#########################
ldap_create_tree() {
    echo "Creating LDAP default tree"
    local dc=""
    local o="example"
    read -r -a root <<< "$(tr ',;' ' ' <<< "${LDAP_ROOT}")"
    for attr in "${root[@]}"; do
        if [[ $attr = dc=* ]] && [[ -z "$dc" ]]; then
            dc="${attr:3}"
        elif [[ $attr = o=* ]] && [[ $o = "example" ]]; then
            o="${attr:2}"
        fi
    done
    cat > "${LDAP_SHARE_DIR}/tree.ldif" << EOF
# Root creation
dn: $LDAP_ROOT
objectClass: dcObject
objectClass: organization
dc: $dc
o: $o

dn: ${LDAP_USER_OU/#/ou=},${LDAP_ROOT}
objectClass: organizationalUnit
ou: users

dn: ${LDAP_GROUP_OU/#/ou=},${LDAP_ROOT}
objectClass: organizationalUnit
ou: groups

EOF
    read -r -a users <<< "$(tr ',;' ' ' <<< "${LDAP_USERS}")"
    read -r -a passwords <<< "$(tr ',;' ' ' <<< "${LDAP_PASSWORDS}")"
    local index=0
    for user in "${users[@]}"; do
        cat >> "${LDAP_SHARE_DIR}/tree.ldif" << EOF
# User $user creation
dn: ${user/#/cn=},${LDAP_USER_OU/#/ou=},${LDAP_ROOT}
cn: User$((index + 1 ))
sn: Bar$((index + 1 ))
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
userPassword: ${passwords[$index]}
uid: $user
uidNumber: $((index + 1000 ))
gidNumber: $((index + 1000 ))
homeDirectory: /home/${user}

EOF
        index=$((index + 1 ))
    done
    cat >> "${LDAP_SHARE_DIR}/tree.ldif" << EOF
# Group creation
dn: ${LDAP_GROUP/#/cn=},${LDAP_GROUP_OU/#/ou=},${LDAP_ROOT}
cn: $LDAP_GROUP
objectClass: groupOfNames
# User group membership
EOF

    for user in "${users[@]}"; do
        cat >> "${LDAP_SHARE_DIR}/tree.ldif" << EOF
member: ${user/#/cn=},${LDAP_USER_OU/#/ou=},${LDAP_ROOT}
EOF
    done

    ldapadd -f "${LDAP_SHARE_DIR}/tree.ldif" -H "ldapi:///" -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD"
}

########################
# Add custom LDIF files
# Globals:
#   LDAP_*
# Arguments:
#   None
# Returns
#   None
#########################
ldap_add_custom_ldifs() {
    echo "Loading custom LDIF files..."
    echo "Ignoring LDAP_USERS, LDAP_PASSWORDS, LDAP_USER_OU, LDAP_GROUP_OU and LDAP_GROUP environment variables..."
    find "$LDAP_CUSTOM_LDIF_DIR" -maxdepth 1 \( -type f -o -type l \) -iname '*.ldif' -print0 | sort -z | xargs --null -I{} bash -c "ldapadd -f {} -H 'ldapi:///' -D \"$LDAP_ADMIN_DN\" -w \"$LDAP_ADMIN_PASSWORD\""
}

########################
# OpenLDAP configure permissions
# Globals:
#   LDAP_*
# Arguments:
#   None
# Returns:
#   None
#########################
ldap_configure_permissions() {
    if am_i_root; then
        chown -R "$LDAP_DAEMON_USER:$LDAP_DAEMON_GROUP" "$LDAP_SHARE_DIR" "$LDAP_DATA_DIR" "$LDAP_ONLINE_CONF_DIR" "$LDAP_VAR_DIR"
    fi
}

########################
# Initialize OpenLDAP server
# Globals:
#   LDAP_*
# Arguments:
#   None
# Returns:
#   None
#########################
ldap_initialize() {
    echo "Initializing OpenLDAP..."
    mkdir -p "$LDAP_DATA_DIR"
    mkdir -p "$LDAP_ONLINE_CONF_DIR"
    ldap_configure_permissions
    if ! is_dir_empty "$LDAP_DATA_DIR"; then
        echo "Using persisted data"
    else
        # Create OpenLDAP online configuration
        ldap_create_online_configuration
        ldap_start_bg
        ldap_admin_credentials
        if ! is_boolean_yes "$LDAP_ALLOW_ANON_BINDING"; then
            ldap_disable_anon_binding
        fi
        # Initialize OpenLDAP with schemas/tree structure
        if is_boolean_yes "$LDAP_ADD_SCHEMAS"; then
            ldap_add_schemas
        fi
        if [[ -f "$LDAP_CUSTOM_SCHEMA_FILE" ]]; then
            ldap_add_custom_schema
        fi
        if ! is_dir_empty "$LDAP_CUSTOM_SCHEMA_DIR"; then
            ldap_add_custom_schemas
        fi
        # additional configuration
        if [[ ! "$LDAP_PASSWORD_HASH" == "{SSHA}" ]]; then
            ldap_configure_password_hash
        fi
        if is_boolean_yes "$LDAP_CONFIGURE_PPOLICY"; then
            ldap_configure_ppolicy
        fi
        # enable accesslog overlay
        if is_boolean_yes "$LDAP_ENABLE_ACCESSLOG"; then
            ldap_enable_accesslog
        fi
        # enable syncprov overlay
        if is_boolean_yes "$LDAP_ENABLE_SYNCPROV"; then
            ldap_enable_syncprov
        fi
        # load custom ldifs
        if ! is_dir_empty "$LDAP_CUSTOM_LDIF_DIR"; then
            ldap_add_custom_ldifs
        elif ! is_boolean_yes "$LDAP_SKIP_DEFAULT_TREE"; then
            ldap_create_tree
        else
            echo "Skipping default schemas/tree structure"
        fi
        # enable tls
        if is_boolean_yes "$LDAP_ENABLE_TLS"; then
            ldap_configure_tls
            if is_boolean_yes "$LDAP_REQUIRE_TLS"; then
                ldap_configure_tls_required
            fi
        fi
       ldap_stop
    fi
}

########################
# Run custom initialization scripts
# Globals:
#   LDAP_*
# Arguments:
#   None
# Returns:
#   None
#########################
ldap_custom_init_scripts() {
    if [[ -n $(find /docker-entrypoint-initdb.d/ -type f -regex ".*\.\(sh\)") ]] && [[ ! -f "$LDAP_DATA_DIR/.user_scripts_initialized" ]] ; then
        echo "Loading user's custom files from /docker-entrypoint-initdb.d";
        for f in /docker-entrypoint-initdb.d/*; do
            echo "Executing $f"
            case "$f" in
                *.sh)
                    if [[ -x "$f" ]]; then
                        if ! "$f"; then
                            echo "Failed executing $f" >&2
                            return 1
                        fi
                    else
                        echo "Sourcing $f as it is not executable by the current user, any error may cause initialization to fail" >&2
                        . "$f"
                    fi
                    ;;
                *)
                    echo "Skipping $f, supported formats are: .sh" >&2
                    ;;
            esac
        done
        touch "$LDAP_DATA_DIR"/.user_scripts_initialized
    fi
}

########################
# OpenLDAP configure TLS
# Globals:
#   LDAP_*
# Arguments:
#   None
# Returns:
#   None
#########################
ldap_configure_tls() {
    echo "Configuring TLS"
    cat > "${LDAP_SHARE_DIR}/certs.ldif" << EOF
dn: cn=config
changetype: modify
replace: olcTLSCACertificateFile
olcTLSCACertificateFile: $LDAP_TLS_CA_FILE
-
replace: olcTLSCertificateFile
olcTLSCertificateFile: $LDAP_TLS_CERT_FILE
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: $LDAP_TLS_KEY_FILE
-
replace: olcTLSVerifyClient
olcTLSVerifyClient: $LDAP_TLS_VERIFY_CLIENTS
EOF
    if [[ -f "$LDAP_TLS_DH_PARAMS_FILE" ]]; then
        cat >> "${LDAP_SHARE_DIR}/certs.ldif" << EOF
-
replace: olcTLSDHParamFile
olcTLSDHParamFile: $LDAP_TLS_DH_PARAMS_FILE
EOF
    fi
    ldapmodify -Y EXTERNAL -H "ldapi:///" -f "${LDAP_SHARE_DIR}/certs.ldif"
}

########################
# OpenLDAP configure connections to require TLS
# Globals:
#   LDAP_*
# Arguments:
#   None
# Returns:
#   None
#########################
ldap_configure_tls_required() {
    echo "Configuring LDAP connections to require TLS"
    cat > "${LDAP_SHARE_DIR}/tls_required.ldif" << EOF
dn: cn=config
changetype: modify
add: olcSecurity
olcSecurity: tls=1
EOF
    ldapmodify -Y EXTERNAL -H "ldapi:///" -f "${LDAP_SHARE_DIR}/tls_required.ldif"
}

########################
# OpenLDAP enable module
# Globals:
#   LDAP_*
# Arguments:
#   $1: Module path
#   $2: Module file name
# Returns:
#   None
#########################
ldap_load_module() {
    echo "Enable LDAP $2 module from $1"
    cat > "${LDAP_SHARE_DIR}/enable_module_$2.ldif" << EOF
dn: cn=module,cn=config
cn: module
objectClass: olcModuleList
olcModulePath: $1
olcModuleLoad: $2
EOF
    ldapadd -Y EXTERNAL -H "ldapi:///" -f "${LDAP_SHARE_DIR}/enable_module_$2.ldif"
}

########################
# OpenLDAP configure ppolicy
# Globals:
#   LDAP_*
# Arguments:
#   None
# Returns:
#   None
#########################
ldap_configure_ppolicy() {
    echo "Configuring LDAP ppolicy"
    ldap_load_module "/opt/openldap/lib/openldap" "ppolicy.so"
    # create configuration
    cat > "${LDAP_SHARE_DIR}/ppolicy_create_configuration.ldif" << EOF
dn: olcOverlay={0}ppolicy,olcDatabase={2}mdb,cn=config
objectClass: olcOverlayConfig
objectClass: olcPPolicyConfig
olcOverlay: {0}ppolicy
EOF
    ldapadd -Q -Y EXTERNAL -H "ldapi:///" -f "${LDAP_SHARE_DIR}/ppolicy_create_configuration.ldif"
    # enable ppolicy_hash_cleartext
    if is_boolean_yes "$LDAP_PPOLICY_HASH_CLEARTEXT"; then
        echo "Enabling ppolicy_hash_cleartext"
        cat > "${LDAP_SHARE_DIR}/ppolicy_configuration_hash_cleartext.ldif" << EOF
dn: olcOverlay={0}ppolicy,olcDatabase={2}mdb,cn=config
changetype: modify
add: olcPPolicyHashCleartext
olcPPolicyHashCleartext: TRUE
EOF
    ldapmodify -Q -Y EXTERNAL -H "ldapi:///" -f "${LDAP_SHARE_DIR}/ppolicy_configuration_hash_cleartext.ldif"
    fi
    # enable ppolicy_use_lockout
    if is_boolean_yes "$LDAP_PPOLICY_USE_LOCKOUT"; then
        echo "Enabling ppolicy_use_lockout"
        cat > "${LDAP_SHARE_DIR}/ppolicy_configuration_use_lockout.ldif" << EOF
dn: olcOverlay={0}ppolicy,olcDatabase={2}mdb,cn=config
changetype: modify
add: olcPPolicyUseLockout
olcPPolicyUseLockout: TRUE
EOF
        ldapmodify -Q -Y EXTERNAL -H "ldapi:///" -f "${LDAP_SHARE_DIR}/ppolicy_configuration_use_lockout.ldif"
    fi
}

########################
# OpenLDAP configure olcPasswordHash
# Globals:
#   LDAP_*
# Arguments:
#   None
# Returns:
#   None
#########################
ldap_configure_password_hash() {
    echo "Configuring LDAP olcPasswordHash"
    cat > "${LDAP_SHARE_DIR}/password_hash.ldif" << EOF
dn: olcDatabase={-1}frontend,cn=config
changetype: modify
add: olcPasswordHash
olcPasswordHash: $LDAP_PASSWORD_HASH
EOF
    ldapmodify -Y EXTERNAL -H "ldapi:///" -f "${LDAP_SHARE_DIR}/password_hash.ldif"
}

########################
# OpenLDAP configure Access Logging
# Globals:
#   LDAP_*
# Arguments:
#   None
# Returns:
#   None
#########################
ldap_enable_accesslog() {
    echo "Configure Access Logging"
    # Add indexes
    cat > "${LDAP_SHARE_DIR}/accesslog_add_indexes.ldif" << EOF
dn: olcDatabase={2}mdb,cn=config
changetype: modify
add: olcDbIndex
olcDbIndex: entryCSN eq
-
add: olcDbIndex
olcDbIndex: entryUUID eq
EOF
    ldapmodify -Y EXTERNAL -H "ldapi:///" -f "${LDAP_SHARE_DIR}/accesslog_add_indexes.ldif"
    # Load module
    ldap_load_module "/opt/openldap/lib/openldap" "accesslog.so"
    # Create AccessLog database
    cat > "${LDAP_SHARE_DIR}/accesslog_create_accesslog_database.ldif" << EOF
dn: olcDatabase={3}mdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcMdbConfig
olcDatabase: {3}mdb
olcDbDirectory: $LDAP_ACCESSLOG_DATA_DIR
olcSuffix: $LDAP_ACCESSLOG_DB
olcRootDN: $LDAP_ACCESSLOG_ADMIN_DN
olcRootPW: $LDAP_ENCRYPTED_ACCESSLOG_ADMIN_PASSWORD
olcDbIndex: default eq
olcDbIndex: entryCSN,objectClass,reqEnd,reqResult,reqStart
EOF
    mkdir "${LDAP_ACCESSLOG_DATA_DIR}"
    ldapadd -Q -Y EXTERNAL -H "ldapi:///" -f "${LDAP_SHARE_DIR}/accesslog_create_accesslog_database.ldif"
    # Add AccessLog overlay
    cat > "${LDAP_SHARE_DIR}/accesslog_create_overlay_configuration.ldif" << EOF
dn: olcOverlay=accesslog,olcDatabase={2}mdb,cn=config
objectClass: olcOverlayConfig
objectClass: olcAccessLogConfig
olcOverlay: accesslog
olcAccessLogDB: $LDAP_ACCESSLOG_DB
olcAccessLogOps: $LDAP_ACCESSLOG_LOGOPS
olcAccessLogSuccess: $LDAP_ACCESSLOG_LOGSUCCESS
olcAccessLogPurge: $LDAP_ACCESSLOG_LOGPURGE
olcAccessLogOld: $LDAP_ACCESSLOG_LOGOLD
olcAccessLogOldAttr: $LDAP_ACCESSLOG_LOGOLDATTR
EOF
    echo "adding accesslog_create_overlay_configuration.ldif"
    ldapadd -Q -Y EXTERNAL -H "ldapi:///" -f "${LDAP_SHARE_DIR}/accesslog_create_overlay_configuration.ldif"
}

########################
# OpenLDAP configure Sync Provider
# Globals:
#   LDAP_*
# Arguments:
#   None
# Returns:
#   None
#########################
ldap_enable_syncprov() {
    echo "Configure Sync Provider"
    # Load module
    ldap_load_module "/opt/openldap/lib/openldap" "syncprov.so"
    # Add Sync Provider overlay
    cat > "${LDAP_SHARE_DIR}/syncprov_create_overlay_configuration.ldif" << EOF
dn: olcOverlay=syncprov,olcDatabase={2}mdb,cn=config
objectClass: olcOverlayConfig
objectClass: olcSyncProvConfig
olcOverlay: syncprov
olcSpCheckpoint: $LDAP_SYNCPROV_CHECKPPOINT
olcSpSessionLog: $LDAP_SYNCPROV_SESSIONLOG
EOF
    ldapadd -Q -Y EXTERNAL -H "ldapi:///" -f "${LDAP_SHARE_DIR}/syncprov_create_overlay_configuration.ldif"
}
