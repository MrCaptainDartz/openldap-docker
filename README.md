# OpenLDAP Docker image from source

## TL;DR
This project provides a Dockerfile and scripts used to build a docker image from official openldap sources
This work is partially based on the [Bitnami OpenLDAP image](https://github.com/bitnami/containers/tree/main/bitnami/openldap), except the build-from-source part, and therefore uses the same environment variable names

## What is OpenLDAP?

> OpenLDAP is the open-source solution for LDAP (Lightweight Directory Access Protocol). It is a protocol used to  store and retrieve data from a hierarchical directory structure such as in databases.

[Overview of OpenLDAP](https://openldap.org/)

## Build this image

This project was made with the goal of building OpenLDAP from source. No pre-built images are available on Docker Repositories.

1. Clone this repository and cd into it
2. Change the first line of the Dockerfile ```ARG OPENLDAP_VERSION=<version>``` and replace version using the one you want to build (This dockerfile has been tested only on 2.6.9)
3. Change the second line of the Dockerfile ```ARG DOWNLOAD_MIRROR="<mirror_url>"``` and replace mirror_url using the one you want. You can find some of them directly on [OpenLDAP Website](https://www.openldap.org/software/download/)
4. 
* To build directly using docker compose, please see [this example](#using-a-docker-compose-file)
* To build from command line :
```console
docker build -t openldap-docker:<version> ./
```

## Connecting to other containers

Using [Docker container networking](https://docs.docker.com/engine/userguide/networking/), a different server running inside a container can easily be accessed by your application containers and vice-versa.

Containers attached to the same network can communicate with each other using the container name as the hostname.

### Using a Docker Compose file

When not specified, Docker Compose automatically sets up a new network and attaches all deployed services to that network. However, we will explicitly define a new `bridge` network named `my-network`. In this example we assume that you want to connect to the OpenLDAP server from your own custom application image which is identified in the following snippet by the service name `myapp`.

```yaml
networks:
  my-network:
    driver: bridge
services:
  openldap:
    build: /PATH/TO/THIS/REPOSITORY
    image: openldap-docker:<version>
    ports:
      - '1389:1389'
      - '1636:1636'
    environment:
      - LDAP_ADMIN_USERNAME=admin
      - LDAP_ADMIN_PASSWORD=adminpassword
      - LDAP_USERS=user01,user02
      - LDAP_PASSWORDS=password1,password2
    networks:
      - my-network
    volumes:
      - 'openldap_data:/openldap'
  myapp:
    image: 'YOUR_APPLICATION_IMAGE'
    networks:
      - my-network
volumes:
  openldap_data:
    driver: local
```

> **IMPORTANT**:
>
> 1. Please update the **/PATH/TO/THIS/REPOSITORY** placeholder in the above snippet with the path to this repository
> 2. Please update the **<version>** placeholder in the above snippet with the path to this repository
> 3. Please update the **YOUR_APPLICATION_IMAGE** placeholder in the above snippet with your application image
> 4. In your application container, use the hostname `openldap` to connect to the OpenLDAP server

Launch the containers using:

```console
docker-compose up -d
```

## Configuration

Docker OpenLDAP can be easily setup with the following environment variables:

* `LDAP_PORT_NUMBER`: The port OpenLDAP is listening for requests. Priviledged port is supported (e.g. `389`). Default: **1389** (non privileged port).
* `LDAP_ROOT`: LDAP baseDN (or suffix) of the LDAP tree. Default: **dc=example,dc=org**
* `LDAP_ADMIN_USERNAME`: LDAP database admin user. Default: **admin**
* `LDAP_ADMIN_PASSWORD`: LDAP database admin password. Default: **adminpassword**
* `LDAP_ADMIN_PASSWORD_FILE`: Path to a file that contains the LDAP database admin user password. This will override the value specified in `LDAP_ADMIN_PASSWORD`. No defaults.
* `LDAP_CONFIG_ADMIN_ENABLED`: Whether to create a configuration admin user. Default: **no**.
* `LDAP_CONFIG_ADMIN_USERNAME`: LDAP configuration admin user. This is separate from `LDAP_ADMIN_USERNAME`. Default: **admin**.
* `LDAP_CONFIG_ADMIN_PASSWORD`: LDAP configuration admin password. Default: **configpassword**.
* `LDAP_CONFIG_ADMIN_PASSWORD_FILE`: Path to a file that contains the LDAP configuration admin user password. This will override the value specified in `LDAP_CONFIG_ADMIN_PASSWORD`. No defaults.
* `LDAP_USERS`: Comma separated list of LDAP users to create in the default LDAP tree. Default: **user01,user02**
* `LDAP_PASSWORDS`: Comma separated list of passwords to use for LDAP users. Default: **user01,user02**
* `LDAP_USER_OU`: Name for the user's organizational unit. Default: **users**
* `LDAP_GROUP_OU`: Name for the group's organizational unit. Default: **groups**
* `LDAP_USER_DC`: DC for the users' organizational unit. **DEPRECATED** Please use `LDAP_USER_OU` and `LDAP_GROUP_OU` instead.
* `LDAP_GROUP`: Group used to group created users. Default: **readers**
* `LDAP_ADD_SCHEMAS`: Whether to add the schemas specified in `LDAP_EXTRA_SCHEMAS`. Default: **yes**
* `LDAP_EXTRA_SCHEMAS`: Extra schemas to add, among OpenLDAP's distributed schemas. Default: **cosine, inetorgperson, nis**
* `LDAP_SKIP_DEFAULT_TREE`: Whether to skip creating the default LDAP tree based on `LDAP_USERS`, `LDAP_PASSWORDS`, `LDAP_USER_OU`, `LDAP_GROUP_OU` and `LDAP_GROUP`. Please note that this will **not** skip the addition of schemas or importing of LDIF files. Default: **no**
* `LDAP_CUSTOM_LDIF_DIR`: Location of a directory that contains LDIF files that should be used to bootstrap the database. Only files ending in `.ldif` will be used. Default LDAP tree based on the `LDAP_USERS`, `LDAP_PASSWORDS`, `LDAP_USER_OU`, `LDAP_GROUP_OU` and `LDAP_GROUP` will be skipped when `LDAP_CUSTOM_LDIF_DIR` is used. When using this it will override the usage of `LDAP_USERS`, `LDAP_PASSWORDS`, `LDAP_USER_OU`, `LDAP_GROUP_OU` and `LDAP_GROUP`. You should set `LDAP_ROOT` to your base to make sure the `olcSuffix` configured on the database matches the contents imported from the LDIF files. Default: **/ldifs**
* `LDAP_CUSTOM_SCHEMA_FILE`: Location of a custom internal schema file that could not be added as custom ldif file (i.e. containing some `structuralObjectClass`). Default is **/schema/custom.ldif**"
* `LDAP_CUSTOM_SCHEMA_DIR`: Location of a directory containing custom internal schema files that could not be added as custom ldif files (i.e. containing some `structuralObjectClass`). This can be used in addition to or instead of `LDAP_CUSTOM_SCHEMA_FILE` (above) to add multiple schema files. Default: **/schemas**
* `LDAP_ULIMIT_NOFILES`: Maximum number of open file descriptors. Default: **1024**.
* `LDAP_ALLOW_ANON_BINDING`: Allow anonymous bindings to the LDAP server. Default: **yes**.
* `LDAP_LOGLEVEL`: Set the loglevel for the OpenLDAP server (see <https://www.openldap.org/doc/admin26/slapdconfig.html> for possible values). Default: **256**.
* `LDAP_PASSWORD_HASH`: Hash to be used in generation of user passwords. Must be one of {SSHA}, {SHA}, {SMD5}, {MD5}, {CRYPT}, and {CLEARTEXT}. Default: **{SSHA}**.
* `LDAP_CONFIGURE_PPOLICY`: Enables the ppolicy module and creates an empty configuration. Default: **no**.
* `LDAP_PPOLICY_USE_LOCKOUT`: Whether bind attempts to locked accounts will always return an error. Will only be applied with `LDAP_CONFIGURE_PPOLICY` active. Default: **no**.
* `LDAP_PPOLICY_HASH_CLEARTEXT`: Whether plaintext passwords should be hashed automatically. Will only be applied with `LDAP_CONFIGURE_PPOLICY` active. Default: **no**.

Other special variables can be found in the script entrypoint.sh

You can bootstrap the contents of your database by putting LDIF files in the directory `/ldifs` (or the one you define in `LDAP_CUSTOM_LDIF_DIR`). Those may only contain content underneath your base DN (set by `LDAP_ROOT`). You can **not** set configuration for e.g. `cn=config` in those files.

Check the official [OpenLDAP Configuration Reference](https://www.openldap.org/doc/admin26/guide.html) for more information about how to configure OpenLDAP.

### Data Persistence

To ensure that the OpenLDAP state is retained across container restarts and updates, it is recommended to mount a volume at `/openldap`.

### Overlays

Overlays are dynamic modules that can be added to an OpenLDAP server to extend or modify its functionality.

#### Access Logging

This overlay can record accesses to a given backend database on another database.

* `LDAP_ENABLE_ACCESSLOG`: Enables the accesslog module with the following configuration defaults unless specified otherwise. Default: **no**.
* `LDAP_ACCESSLOG_ADMIN_USERNAME`: Admin user for accesslog database. Default: **admin**.
* `LDAP_ACCESSLOG_ADMIN_PASSWORD`: Admin password for accesslog database. Default: **accesspassword**.
* `LDAP_ACCESSLOG_DB`: The DN (Distinguished Name) of the database where the access log entries will be stored. Will only be applied with `LDAP_ENABLE_ACCESSLOG` active. Default: **cn=accesslog**.
* `LDAP_ACCESSLOG_LOGOPS`: Specify which types of operations to log. Valid aliases for common sets of operations are: writes, reads, session or all. Will only be applied with `LDAP_ENABLE_ACCESSLOG` active. Default: **writes**.
* `LDAP_ACCESSLOG_LOGSUCCESS`: Whether successful operations should be logged. Will only be applied with `LDAP_ENABLE_ACCESSLOG` active. Default: **TRUE**.
* `LDAP_ACCESSLOG_LOGPURGE`: When and how often old access log entries should be purged. Format `"dd+hh:mm"`. Will only be applied with `LDAP_ENABLE_ACCESSLOG` active. Default: **07+00:00 01+00:00**.
* `LDAP_ACCESSLOG_LOGOLD`: An LDAP filter that determines which entries should be logged. Will only be applied with `LDAP_ENABLE_ACCESSLOG` active. Default: **(objectClass=*)**.
* `LDAP_ACCESSLOG_LOGOLDATTR`: Specifies an attribute that should be logged. Will only be applied with `LDAP_ENABLE_ACCESSLOG` active. Default: **objectClass**.

Check the official page [OpenLDAP, Overlays, Access Logging](https://www.openldap.org/doc/admin26/overlays.html#Access%20Logging) for detailed configuration information.

#### Sync Provider

* `LDAP_ENABLE_SYNCPROV`: Enables the syncrepl module with the following configuration defaults unless specified otherwise. Default: **no**.
* `LDAP_SYNCPROV_CHECKPPOINT`: For every 100 operations or 10 minutes, which ever is sooner, the contextCSN will be checkpointed. Will only be applied with `LDAP_ENABLE_SYNCPROV` active. Default: **100 10**.
* `LDAP_SYNCPROV_SESSIONLOG`: The maximum number of session log entries the session log can record. Will only be applied with `LDAP_ENABLE_SYNCPROV` active. Default: **100**.

Check the official page [OpenLDAP, Overlays, Sync Provider](https://www.openldap.org/doc/admin26/overlays.html#Sync%20Provider) for detailed configuration information.

### Securing OpenLDAP traffic

OpenLDAP clients and servers are capable of using the Transport Layer Security (TLS) framework to provide integrity and confidentiality protections and to support LDAP authentication using the SASL EXTERNAL mechanism. Should you desire to enable this optional feature, you may use the following environment variables to configure the application:

* `LDAP_ENABLE_TLS`: Whether to enable TLS for traffic or not. Defaults to `no`.
* `LDAP_REQUIRE_TLS`: Whether connections must use TLS. Will only be applied with `LDAP_ENABLE_TLS` active. Defaults to `no`.
* `LDAP_LDAPS_PORT_NUMBER`: Port used for TLS secure traffic. Priviledged port is supported (e.g. `636`). Default: **1636** (non privileged port).
* `LDAP_TLS_CERT_FILE`: File containing the certificate file for the TLS traffic. No defaults.
* `LDAP_TLS_KEY_FILE`: File containing the key for certificate. No defaults.
* `LDAP_TLS_CA_FILE`: File containing the CA of the certificate. No defaults.
* `LDAP_TLS_DH_PARAMS_FILE`: File containing the DH parameters. No defaults.

This new feature is not mutually exclusive, which means it is possible to listen to both TLS and non-TLS connection simultaneously. To use TLS you can use the URI `ldaps://openldap:1636` or use the non-TLS URI forcing ldap to use TLS `ldap://openldap:1389 -ZZ`.

Modifying the `docker-compose.yml` file present in this repository:

    ```yaml
    services:
      openldap:
      ...
        environment:
          ...
          - LDAP_ENABLE_TLS=yes
          - LDAP_TLS_CERT_FILE=/opt/openldap/certs/openldap.crt
          - LDAP_TLS_KEY_FILE=/opt/openldap/certs/openldap.key
          - LDAP_TLS_CA_FILE=/opt/openldap/certs/openldapCA.crt
        ...
        volumes:
          - /path/to/certs:/opt/openldap/certs
          - /path/to/openldap-data-persistence:/openldap/
      ...
    ```

### Run behind load balancer

OpenLDAP supports the HAProxy proxy protocol version 2 to detect real client IP that is masked when server runs behind load balancer. You can enable and configure this feature with the following environment variables:

* `LDAP_ENABLE_PROXYPROTO`: Whether to enable proxy protocol support for traffic or not. Defaults to `no`.
* `LDAP_PROXYPROTO_PORT_NUMBER`: The port OpenLDAP is listening for requests that is wrapped in proxy protocol. Default: the **LDAP_PORT_NUMBER** value.
* `LDAP_PROXYPROTO_LDAPS_PORT_NUMBER`: Port used for TLS secure traffic that is wrapped in proxy protocol. Default: the **LDAP_LDAPS_PORT_NUMBER** value.

Enabling this feature will replace regular and TLS ports with proxy protocol capable analogs. To use both port types, set **LDAP_PROXYPROTO_PORT_NUMBER** to some different value than **LDAP_PORT_NUMBER**. The same statement applied to **LDAP_PROXYPROTO_LDAPS_PORT_NUMBER** and **LDAP_LDAPS_PORT_NUMBER** pair.

**Security warning**: To prevent client IP spoofing, it is highly advised to secure the proxy protocol capable ports by firewall that allow traffic only from load balancer hosts.

Check the official page [OpenLDAP, Running slapd, Command-Line Options](https://www.openldap.org/doc/admin26/runningslapd.html#Command-Line%20Options) for additional information.

### Initializing a new instance

This image allows you to use your custom scripts to initialize a fresh instance.

The allowed script extension is `.sh`, all scripts are executed in alphabetical order.

1. You can include them in image by placing scripts in the scripts/entrypoint folder before executing docker build
2. You can mount your scripts directly into the folder `/docker-entrypoint-initdb.d/` of the container

Scripts are executed are after the initilization and before the startup of the OpenLDAP service.

## Logging

The image sends the container logs to `stdout`. To view the logs:

```console
docker logs openldap
```

You can configure the containers [logging driver](https://docs.docker.com/engine/admin/logging/overview/) using the `--log-driver` option if you wish to consume the container logs differently. In the default configuration docker uses the `json-file` driver.