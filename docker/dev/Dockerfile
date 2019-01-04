FROM elixir:alpine

ENV INSTALL_BASE=/app
ARG MIX_ENV

WORKDIR $INSTALL_BASE
COPY requirements.txt $INSTALL_BASE/

RUN apk --no-cache update && \
    apk --no-cache add bash coreutils perl \
        libffi openssl vim gnupg \
        openssh perl-json bind-tools \
        bash curl tar gcc libc-dev libffi-dev \
        linux-headers make python3-dev && \
    pip3 install --upgrade pip && \
    pip3 install -r requirements.txt

COPY cli /app/cli
COPY profile.sh /etc/profile.d/profile.sh.in

ARG BUILD_VERSION
RUN echo $BUILD_VERSION > .build_version && \
    apk --no-cache update && \
    pip3 install --upgrade -r /app/requirements.txt && \
    sed -e 's/{{build}}/'$BUILD_VERSION'/' /etc/profile.d/profile.sh.in > /etc/profile.d/profile.sh && \
    rm /etc/profile.d/profile.sh.in

VOLUME /local
VOLUME /backup

WORKDIR /app/cli
ENTRYPOINT
CMD /bin/sh
