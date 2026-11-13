FROM debian:bullseye

ARG DEBIAN_FRONTEND=noninteractive

RUN printf 'deb http://archive.debian.org/debian bullseye main\ndeb http://archive.debian.org/debian-security bullseye-security main\n' > /etc/apt/sources.list \
 && echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99archive \
 && apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      build-essential crossbuild-essential-arm64 autoconf automake libtool \
      pkg-config gettext cmake git wget ca-certificates xz-utils bzip2 \
      vim-common libplist-utils \
 && apt-get install -y -qq --no-install-recommends autopoint \
 && test -x /usr/bin/autopoint \
 && dpkg --add-architecture arm64 \
 && printf 'deb [arch=arm64] http://archive.debian.org/debian bullseye main\ndeb [arch=arm64] http://archive.debian.org/debian-security bullseye-security main\n' >> /etc/apt/sources.list \
 && apt-get update -qq \
 && mkdir -p /opt/debs && cd /opt/debs \
 && apt-get download -qq \
      libavahi-client-dev:arm64 libavahi-common-dev:arm64 \
      libavahi-client3:arm64 libavahi-common3:arm64 libdbus-1-3:arm64 libdbus-1-dev:arm64 libsystemd0:arm64 \
      libpulse-dev:arm64 libpulse0:arm64 \
      uuid-dev:arm64 libuuid1:arm64 \
      libssl-dev:arm64 libssl1.1:arm64 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /work
