FROM postgres:9.6-alpine

# used for 'date' command with -d
RUN apk --no-cache add coreutils perl python3 \
        libffi openssl vim gnupg \
        openssh perl-json bind-tools \
        bash curl tar gcc libc-dev libffi-dev \
        linux-headers make python3-dev && \
    pip3 install --upgrade pip && \
    pip3 install rfxcmd s3cmd # or do we want aws?

WORKDIR /app
COPY requirements.txt /app
RUN pip3 install --upgrade pip && \
   pip3 install -r /app/requirements.txt

COPY inside /app/bin
COPY profile.sh /etc/profile.d/profile.sh.in

ARG BUILD_VERSION
RUN echo $BUILD_VERSION > .build_version && \
    apk --no-cache update && \
    pip3 install --upgrade -r /app/requirements.txt && \
    sed -e 's/{{build}}/'$BUILD_VERSION'/' /etc/profile.d/profile.sh.in > /etc/profile.d/profile.sh && \
    rm /etc/profile.d/profile.sh.in

VOLUME /local
VOLUME /backup
VOLUME /root/.aws

WORKDIR /app/bin
ENTRYPOINT
CMD /bin/sh
