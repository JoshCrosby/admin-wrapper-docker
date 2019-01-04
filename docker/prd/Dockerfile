FROM elixir:alpine

ENV INSTALL_BASE=/app/glados
ENV PATH=$PATH:/usr/local/bin
ARG MIX_ENV

WORKDIR $INSTALL_BASE

# onelogin CA is not being accepted by default, hardcode it
# we don't need anything else from docker/
COPY docker/onelogin-ca.crt $INSTALL_BASE/docker/

RUN apk --no-cache update && \
    apk --no-cache add python3-dev libffi ca-certificates \
        nodejs yarn libffi-dev gcc libc-dev tar make && \
    pip3 --no-cache-dir install rfxcmd && \
    rm -rf ~/.pip/cache $PWD/build/ && \
    mix local.hex --force && \
    mix local.rebar --force && \
    mix archive.install --force https://github.com/phoenixframework/archives/raw/master/phx_new.ez && \
    mkdir /etc/openldap ; \
    echo "TLS_CACERT /app/docker/onelogin-ca.crt" > /etc/openldap/ldap.conf

COPY docker/ $INSTALL_BASE/docker/
COPY app/ $INSTALL_BASE/app/
WORKDIR $INSTALL_BASE/app/

ARG BUILD_VERSION

# this first line puts $BUILD_VERSION into mix.exs as version
RUN sed -i -e 's/^\(\s*\)build_version: "[0-9].*$/\1build_version: "'$BUILD_VERSION'",/' mix.exs && \
    mix deps.get && \
    mix deps.compile && \
    (cd assets && \
     yarn install && \
     ./node_modules/.bin/brunch build --production ) && \
    mix phx.digest

CMD launch app
