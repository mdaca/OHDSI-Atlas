# Build the source
FROM docker.io/library/node:18.14.1-alpine@sha256:045b1a1c90bdfd8fcaad0769922aa16c401e31867d8bf5833365b0874884bbae as builder

WORKDIR /code

# First install dependencies. This part will be cached as long as
# the package.json file remains identical.
COPY package.json /code/
RUN npm install

# Build code
COPY ./build /code/build
COPY ./js /code/js
RUN npm run build:docker

# Statically pre-compress all output files to be served
COPY ./index.html /code/index.html
RUN find . -type f "(" \
        -name "*.css" \
        -o -name "*.html" \
        -o -name "*.js" ! -name "config-local.js" \
        -o -name "*.json" \
        -o -name "*.svg" \
        -o -name "*.xml" \
      ")" -print0 \
      | xargs -0 -n 1 gzip -kf


# Nginx public dockerfile, replaces default Atlas Nginx prod image:
FROM nginx:1.26.1-alpine-slim

ENV NJS_VERSION   0.8.4
ENV NJS_RELEASE   2

RUN set -x \
    && apkArch="$(cat /etc/apk/arch)" \
    && nginxPackages=" \
        nginx=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-xslt=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-geoip=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-image-filter=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-njs=${NGINX_VERSION}.${NJS_VERSION}-r${NJS_RELEASE} \
    " \
# install prerequisites for public key and pkg-oss checks
    && apk add --no-cache --virtual .checksum-deps \
        openssl \
    && case "$apkArch" in \
        x86_64|aarch64) \
# arches officially built by upstream
            apk add -X "https://nginx.org/packages/alpine/v$(egrep -o '^[0-9]+\.[0-9]+' /etc/alpine-release)/main" --no-cache $nginxPackages \
            ;; \
        *) \
# we're on an architecture upstream doesn't officially build for
# let's build binaries from the published packaging sources
            set -x \
            && tempDir="$(mktemp -d)" \
            && chown nobody:nobody $tempDir \
            && apk add --no-cache --virtual .build-deps \
                gcc \
                libc-dev \
                make \
                openssl-dev \
                pcre2-dev \
                zlib-dev \
                linux-headers \
                libxslt-dev \
                gd-dev \
                geoip-dev \
                libedit-dev \
                bash \
                alpine-sdk \
                findutils \
            && su nobody -s /bin/sh -c " \
                export HOME=${tempDir} \
                && cd ${tempDir} \
                && curl -f -O https://hg.nginx.org/pkg-oss/archive/${NGINX_VERSION}-${PKG_RELEASE}.tar.gz \
                && PKGOSSCHECKSUM=\"0db2bf5f86e7c31f23d0e3e7699a5d8a4d9d9b0dc2f98d3e3a31e004df20206270debf6502e4481892e8b64d55fba73fcc8d74c3e0ddfcd2d3f85a17fa02a25e *${NGINX_VERSION}-${PKG_RELEASE}.tar.gz\" \
                && if [ \"\$(openssl sha512 -r ${NGINX_VERSION}-${PKG_RELEASE}.tar.gz)\" = \"\$PKGOSSCHECKSUM\" ]; then \
                    echo \"pkg-oss tarball checksum verification succeeded!\"; \
                else \
                    echo \"pkg-oss tarball checksum verification failed!\"; \
                    exit 1; \
                fi \
                && tar xzvf ${NGINX_VERSION}-${PKG_RELEASE}.tar.gz \
                && cd pkg-oss-${NGINX_VERSION}-${PKG_RELEASE} \
                && cd alpine \
                && make module-geoip module-image-filter module-njs module-xslt \
                && apk index --allow-untrusted -o ${tempDir}/packages/alpine/${apkArch}/APKINDEX.tar.gz ${tempDir}/packages/alpine/${apkArch}/*.apk \
                && abuild-sign -k ${tempDir}/.abuild/abuild-key.rsa ${tempDir}/packages/alpine/${apkArch}/APKINDEX.tar.gz \
                " \
            && cp ${tempDir}/.abuild/abuild-key.rsa.pub /etc/apk/keys/ \
            && apk del --no-network .build-deps \
            && apk add -X ${tempDir}/packages/alpine/ --no-cache $nginxPackages \
            ;; \
    esac \
# remove checksum deps
    && apk del --no-network .checksum-deps \
# if we have leftovers from building, let's purge them (including extra, unnecessary build deps)
    && if [ -n "$tempDir" ]; then rm -rf "$tempDir"; fi \
    && if [ -f "/etc/apk/keys/abuild-key.rsa.pub" ]; then rm -f /etc/apk/keys/abuild-key.rsa.pub; fi \
# Bring in curl and ca-certificates to make registering on DNS SD easier
    && apk add --no-cache curl ca-certificates


#Atlas continued:

# URL where WebAPI can be queried by the client
ENV USE_DYNAMIC_WEBAPI_URL="false"
ENV DYNAMIC_WEBAPI_SUFFIX="/WebAPI/"
ENV WEBAPI_URL="http://localhost:8080/WebAPI/"
ENV CONFIG_PATH="/etc/atlas/config-local.js"
ENV ATLAS_INSTANCE_NAME="OHDSI"
ENV ATLAS_COHORT_COMPARISON_RESULTS_ENABLED="false"
ENV ATLAS_USER_AUTH_ENABLED="false"
ENV ATLAS_PLP_RESULTS_ENABLED="false"
ENV ATLAS_CLEAR_LOCAL_STORAGE="false"
ENV ATLAS_DISABLE_BROWSER_CHECK="false"
ENV ATLAS_ENABLE_PERMISSIONS_MGMT="true"
ENV ATLAS_CACHE_SOURCES="false"
ENV ATLAS_POLL_INTERVAL="60000"
ENV ATLAS_SKIP_LOGIN="false"
ENV ATLAS_USE_EXECUTION_ENGINE="false"
ENV ATLAS_VIEW_PROFILE_DATES="false"
ENV ATLAS_ENABLE_COSTS="false"
ENV ATLAS_SUPPORT_URL="https://github.com/ohdsi/atlas/issues"
ENV ATLAS_SUPPORT_MAIL="atlasadmin@your.org"
ENV ATLAS_FEEDBACK_CONTACTS="For access or questions concerning the Atlas application please contact:"
ENV ATLAS_FEEDBACK_HTML=""
ENV ATLAS_COMPANYINFO_HTML=""
ENV ATLAS_COMPANYINFO_SHOW="true"
ENV ATLAS_DEFAULT_LOCALE="en"

ENV ATLAS_SECURITY_WIN_PROVIDER_ENABLED="false"
ENV ATLAS_SECURITY_WIN_PROVIDER_NAME="Windows"
ENV ATLAS_SECURITY_WIN_PROVIDER_URL="user/login/windows"
ENV ATLAS_SECURITY_WIN_PROVIDER_AJAX="true"
ENV ATLAS_SECURITY_WIN_PROVIDER_ICON="fab fa-windows"

ENV ATLAS_SECURITY_KERB_PROVIDER_ENABLED="false"
ENV ATLAS_SECURITY_KERB_PROVIDER_NAME="Kerberos"
ENV ATLAS_SECURITY_KERB_PROVIDER_URL="user/login/kerberos"
ENV ATLAS_SECURITY_KERB_PROVIDER_AJAX="true"
ENV ATLAS_SECURITY_KERB_PROVIDER_ICON="fab fa-windows"

ENV ATLAS_SECURITY_OID_PROVIDER_ENABLED="false"
ENV ATLAS_SECURITY_OID_PROVIDER_NAME="OpenID Connect"
ENV ATLAS_SECURITY_OID_PROVIDER_URL="user/login/openid"
ENV ATLAS_SECURITY_OID_PROVIDER_AJAX="false"
ENV ATLAS_SECURITY_OID_PROVIDER_ICON="fa fa-openid"

ENV ATLAS_SECURITY_GGL_PROVIDER_ENABLED="false"
ENV ATLAS_SECURITY_GGL_PROVIDER_NAME="Google"
ENV ATLAS_SECURITY_GGL_PROVIDER_URL="user/oauth/google"
ENV ATLAS_SECURITY_GGL_PROVIDER_AJAX="false"
ENV ATLAS_SECURITY_GGL_PROVIDER_ICON="fab fa-google"

ENV ATLAS_SECURITY_FB_PROVIDER_ENABLED="false"
ENV ATLAS_SECURITY_FB_PROVIDER_NAME="Facebook"
ENV ATLAS_SECURITY_FB_PROVIDER_URL="user/oauth/facebook"
ENV ATLAS_SECURITY_FB_PROVIDER_AJAX="false"
ENV ATLAS_SECURITY_FB_PROVIDER_ICON="fab fa-facebook-f"

ENV ATLAS_SECURITY_GH_PROVIDER_ENABLED="false"
ENV ATLAS_SECURITY_GH_PROVIDER_NAME="Github"
ENV ATLAS_SECURITY_GH_PROVIDER_URL="user/oauth/github"
ENV ATLAS_SECURITY_GH_PROVIDER_AJAX="false"
ENV ATLAS_SECURITY_GH_PROVIDER_ICON="fab fa-github"

ENV ATLAS_SECURITY_DB_PROVIDER_ENABLED="false"
ENV ATLAS_SECURITY_DB_PROVIDER_NAME="DB"
ENV ATLAS_SECURITY_DB_PROVIDER_URL="user/login/db"
ENV ATLAS_SECURITY_DB_PROVIDER_AJAX="true"
ENV ATLAS_SECURITY_DB_PROVIDER_ICON="fa fa-database"
ENV ATLAS_SECURITY_DB_PROVIDER_CREDFORM="true"

ENV ATLAS_SECURITY_LDAP_PROVIDER_ENABLED="false"
ENV ATLAS_SECURITY_LDAP_PROVIDER_NAME="LDAP"
ENV ATLAS_SECURITY_LDAP_PROVIDER_URL="user/login/ldap"
ENV ATLAS_SECURITY_LDAP_PROVIDER_AJAX="true"
ENV ATLAS_SECURITY_LDAP_PROVIDER_ICON="fa fa-cubes"
ENV ATLAS_SECURITY_LDAP_PROVIDER_CREDFORM="true"

ENV ATLAS_SECURITY_SAML_PROVIDER_ENABLED="false"
ENV ATLAS_SECURITY_SAML_PROVIDER_NAME="SAML"
ENV ATLAS_SECURITY_SAML_PROVIDER_URL="user/login/saml"
ENV ATLAS_SECURITY_SAML_PROVIDER_AJAX="false"
ENV ATLAS_SECURITY_SAML_PROVIDER_ICON="fab fa-openid"

ENV ATLAS_SECURITY_AD_PROVIDER_ENABLED="false"
ENV ATLAS_SECURITY_AD_PROVIDER_NAME="Active Directory LDAP"
ENV ATLAS_SECURITY_AD_PROVIDER_URL="user/login/ad"
ENV ATLAS_SECURITY_AD_PROVIDER_AJAX="true"
ENV ATLAS_SECURITY_AD_PROVIDER_ICON="fa fa-cubes"
ENV ATLAS_SECURITY_AD_PROVIDER_CREDFORM="true"

# for existing broadsea implementations
ENV ATLAS_SECURITY_PROVIDER_ENABLED="true"
ENV ATLAS_SECURITY_PROVIDER_NAME="none"
ENV ATLAS_SECURITY_PROVIDER_TYPE="none"
ENV ATLAS_SECURITY_USE_AJAX="false"
ENV ATLAS_SECURITY_PROVIDER_ICON="fa-cubes"
ENV ATLAS_SECURITY_USE_FORM="false"

ENV ATLAS_ENABLE_TANDCS="true"
ENV ATLAS_ENABLE_PERSONCOUNT="true"
ENV ATLAS_ENABLE_TAGGING_SECTION="false"
ENV ATLAS_REFRESH_TOKEN_THRESHOLD="240"

# Configure webserver
COPY ./docker/nginx-default.conf /etc/nginx/conf.d/default.conf
COPY ./docker/optimization.conf /etc/nginx/conf.d/optimization.conf
COPY ./docker/30-atlas-env-subst.sh /docker-entrypoint.d/30-atlas-env-subst.sh

# Load code
COPY ./images /usr/share/nginx/html/atlas/images
COPY ./README.md ./LICENSE /usr/share/nginx/html/atlas/
COPY --from=builder /code/index.html* /usr/share/nginx/html/atlas/
COPY --from=builder /code/node_modules /usr/share/nginx/html/atlas/node_modules
COPY --from=builder /code/js /usr/share/nginx/html/atlas/js

# Load Atlas local config with current user, so it can be modified
# with env substitution
COPY --chown=101 docker/config-local.js /usr/share/nginx/html/atlas/js/config-local.js
