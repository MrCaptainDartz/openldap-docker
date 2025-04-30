ARG OPENLDAP_VERSION=2.6.9
ARG DOWNLOAD_MIRROR="https://www.openldap.org/software/download/OpenLDAP/openldap-release"

FROM debian:bookworm-slim AS builder

ARG OPENLDAP_VERSION
ARG DOWNLOAD_MIRROR

#APT Dependencies
RUN apt-get update
RUN apt-get install -y --no-install-recommends build-essential groff-base ca-certificates curl heimdal-multidev libkrb5-26-heimdal libkrb5-dev libevent-2.1-7 libevent-dev libsasl2-dev libssl-dev libltdl-dev libargon2-dev libargon2-1 libcap2-bin libcom-err2 libcrypt1 libgssapi-krb5-2 libk5crypto3 libkeyutils1 libkrb5-3 libkrb5support0 libltdl7 libnsl2 libnss3-tools libodbc2 libperl5.36 libsasl2-2 libssl3 libtirpc3 libwrap0 mdbtools procps psmisc

#Prepare sources 
WORKDIR /tmp
RUN curl -SsLf "${DOWNLOAD_MIRROR}/openldap-${OPENLDAP_VERSION}.tgz" -O
RUN tar xfz openldap-${OPENLDAP_VERSION}.tgz

#Build openldap
WORKDIR /tmp/openldap-${OPENLDAP_VERSION}
RUN ./configure --prefix=/opt/openldap --with-argon2=libargon2 --with-cyrus-sasl --enable-modules --enable-overlays --enable-argon2 --enable-rlookups --enable-spasswd --enable-balancer --enable-ldap
RUN make depend
RUN make
RUN make install

#Build modules
WORKDIR /tmp/openldap-${OPENLDAP_VERSION}/contrib/slapd-modules/autogroup
RUN make prefix=/opt/openldap
RUN make install prefix=/opt/openldap

WORKDIR /tmp/openldap-${OPENLDAP_VERSION}/contrib/slapd-modules/lastbind
RUN make prefix=/opt/openldap
RUN make install prefix=/opt/openldap

WORKDIR /tmp/openldap-${OPENLDAP_VERSION}/contrib/slapd-modules/passwd/pbkdf2
RUN make prefix=/opt/openldap
RUN make install prefix=/opt/openldap

WORKDIR /tmp/openldap-${OPENLDAP_VERSION}/contrib/slapd-modules/passwd/sha2
RUN make prefix=/opt/openldap
RUN make install prefix=/opt/openldap

WORKDIR /tmp/openldap-${OPENLDAP_VERSION}/contrib/slapd-modules/passwd/totp
RUN make prefix=/opt/openldap
RUN make install prefix=/opt/openldap

WORKDIR /tmp/openldap-${OPENLDAP_VERSION}/contrib/slapd-modules/smbk5pwd
RUN make prefix=/opt/openldap HEIMDAL_INC=-I/usr/include/heimdal
RUN make install prefix=/opt/openldap HEIMDAL_INC=-I/usr/include/heimdal

#Final image
FROM debian:bookworm-slim

ARG OPENLDAP_VERSION

#APT Dependencies
RUN apt-get update
RUN apt-get install -y --no-install-recommends nano ca-certificates curl libhdb9-heimdal libkrb5-26-heimdal libevent-2.1-7 libargon2-1 libcap2-bin libcom-err2 libcrypt1 libgssapi-krb5-2 libk5crypto3 libkeyutils1 libkrb5-3 libkrb5support0 libltdl7 libnsl2 libnss3-tools libodbc2 libperl5.36 libsasl2-2 libssl3 libtirpc3 libwrap0 mdbtools procps psmisc

#Cleanup
RUN apt-get autoremove --purge -y curl && \
    apt-get update && apt-get upgrade -y && \
    apt-get clean && rm -rf /var/lib/apt/lists /var/cache/apt/archives

#Copy build
COPY --from=builder /opt/openldap /opt/openldap
RUN chmod g+rwX /opt/openldap
COPY --chmod=755 ./scripts/entrypoint.sh /opt/scripts/entrypoint.sh
COPY --chmod=755 ./scripts/run_openldap.sh /opt/scripts/run_openldap.sh
COPY --chmod=755 ./scripts/lib_openldap.sh /opt/scripts/lib_openldap.sh
COPY --chmod=755 ./scripts/lib_functions.sh /opt/scripts/lib_functions.sh

#Ensure no setuid binaries
RUN find / -perm /6000 -type f -exec chmod a-s {} \; || true

#Create directories and set permissions
RUN mkdir -p /opt/openldap/data /opt/openldap/var /openldap/data /openldap/slapd.d /docker-entrypoint-initdb.d
RUN chmod -R g+rwX /opt/openldap/share /opt/openldap/data /opt/openldap/var /openldap/data /openldap/slapd.d /docker-entrypoint-initdb.d

#Symlinks for docker volume
RUN ln -sf /openldap/slapd.d /opt/openldap/etc/openldap/slapd.d
RUN ln -sf /openldap/data /opt/openldap/var/data

#Set capabilities
RUN setcap CAP_NET_BIND_SERVICE=+eip /opt/openldap/libexec/slapd

#Create slapd user
RUN useradd slapd

ENV PATH="/opt/openldap/bin:/opt/openldap/sbin:/opt/openldap/libexec:$PATH"

COPY ./schema /opt/openldap/etc/openldap/schema/
COPY --chmod=755 ./scripts/entrypoint /docker-entrypoint-initdb.d/

EXPOSE 1389 1636

USER 1001
ENTRYPOINT [ "/opt/scripts/entrypoint.sh" ]
CMD [ "/opt/scripts/run_openldap.sh" ]