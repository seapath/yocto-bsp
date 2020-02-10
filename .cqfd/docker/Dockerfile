FROM ubuntu:18.04

ENV DEBIAN_FRONTEND noninteractive

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV LC_ALL en_US.UTF-8

# Yocto mandatory packages
RUN apt-get update && apt-get install -y --no-install-recommends \
	asciidoc \
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
	libncurses5-dev \
	libsdl1.2-dev \
	libssl-dev \
	locales \
	python \
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
	unzip \
	wget \
	xterm \
	xxd \
	xz-utils \
	zip

# Asciidoctor PDF generator for generating the manual
RUN gem install asciidoctor-pdf --pre -v 1.5.0.rc2

RUN sed -i "s/# en_US\.UTF-8 UTF-8/en_US\.UTF-8 UTF-8/" /etc/locale.gen
RUN locale-gen
RUN dpkg-reconfigure locales
