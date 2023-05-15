# Copyright (C) 2023, RTE (http://www.rte-france.com)
# Copyright (C) 2023 Savoir-faire Linux, Inc.
# SPDX-License-Identifier: Apache-2.0

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND noninteractive

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV LC_ALL en_US.UTF-8

# Yocto mandatory packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    asciidoc \
    ruby-asciidoctor-pdf \
    ruby \
    bash \
    bc \
    bison \
    build-essential \
    ca-certificates \
    chrpath \
    cpio \
    debianutils \
    diffstat \
    file \
    flex \
    gawk \
    gcc-multilib \
    g++-multilib \
    git \
    git-core \
    iputils-ping \
    lbzip2 \
    libelf-dev \
    libmpc-dev \
    libncurses5-dev \
    libsdl1.2-dev \
    libssl-dev \
    locales \
    lz4 \
    pigz \
    python3 \
    python3-pip \
    python3-pexpect \
    rsync \
    socat \
    ssh \
    sshpass \
    subversion \
    swig \
    texinfo \
    tmux \
    unzip \
    wget \
    xterm \
    xxd \
    xz-utils \
    zstd

# Git Proxy Configuration
ADD http://git.yoctoproject.org/cgit/cgit.cgi/poky/plain/scripts/oe-git-proxy /usr/local/bin/oe-git-proxy
RUN chmod +x /usr/local/bin/oe-git-proxy

# Git Proxy Configuration
ADD http://git.yoctoproject.org/cgit/cgit.cgi/poky/plain/scripts/oe-git-proxy /usr/local/bin/oe-git-proxy
RUN chmod +x /usr/local/bin/oe-git-proxy

RUN sed -i "s/# en_US\.UTF-8 UTF-8/en_US\.UTF-8 UTF-8/" /etc/locale.gen
RUN locale-gen
RUN dpkg-reconfigure locales
