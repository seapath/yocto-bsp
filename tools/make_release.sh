#!/usr/bin/env bash

set -e

VERSION=""
FULL_BUILD=false

while [ $# -gt 0 ]; do
    case "$1" in
        --tag)
            VERSION="$2"
            shift 2
            ;;
        --full-build)
            FULL_BUILD=true
            shift
            ;;
        *)
            echo "Usage: $0 [--tag <tag>] [--full-build]"
            exit 1
            ;;
    esac
done

cd $(dirname $0)/..

# Try to the version release from git
if [ -z "$VERSION" ]; then
    VERSION=$(git describe --tags --abbrev=0)
    if [ -z "$VERSION" ]; then
        echo "Could not determine version from git tags, using X.Y.Z"
        VERSION="vX.Y.Z"
    fi
fi

echo "Preparing release for version ${VERSION}"

# Prepare release directory
mkdir -p release-files
.repo/repo/repo manifest -r > release-files/"${VERSION}".xml
cp .cqfd/docker/seapath-release-key release-files/seapath-"${VERSION}"-artifacts-key
cp .cqfd/docker/seapath-release-key.pub release-files/seapath-"${VERSION}"-artifacts-key.pub

# Prepare build environment
cp .cqfd/docker/seapath-release-key.pub keys/ansible_public_ssh_key.pub
cp -f seapath.conf.sample seapath.conf

# Build seapath-flasher image
./build.sh -v -i seapath-flasher --distro seapath-flash --machine seapath-installer
cp build/tmp/deploy/images/seapath-installer/seapath-flasher-seapath-installer.rootfs.wic.gz \
    release-files/seapath-"${VERSION}"-flasher-image.rootfs.wic.gz
cp build/tmp/deploy/images/seapath-installer/seapath-flasher-seapath-installer.rootfs.wic.bmap \
    release-files/seapath-"${VERSION}"-flasher-image.rootfs.wic.bmap

# Build seapath-host-cluster image
./build.sh -v -i seapath-host-efi-swu-image --distro seapath-host
cp build/tmp/deploy/images/seapath-hypervisor/seapath-host-efi-image-seapath-hypervisor.rootfs.wic.gz \
    release-files/seapath-"${VERSION}"-host-cluster-efi-image.rootfs.wic.gz
cp build/tmp/deploy/images/seapath-hypervisor/seapath-host-efi-image-seapath-hypervisor.rootfs.wic.bmap \
        release-files/seapath-"${VERSION}"-host-cluster-efi-image.rootfs.wic.bmap
cp build/tmp/deploy/images/seapath-hypervisor/seapath-host-efi-swu-image-seapath-hypervisor.rootfs.swu \
    release-files/seapath-"${VERSION}"-host-cluster-efi-image.rootfs.swu
cp build/tmp/deploy/images/seapath-hypervisor/seapath-host-efi-image-seapath-hypervisor.rootfs.spdx.json \
    release-files/seapath-"${VERSION}"-host-cluster-efi-image.rootfs.spdx.json

# Build seapath-guest image
./build.sh -v -i seapath-guest-efi-image --distro seapath-guest --machine seapath-vm
cp build/tmp/deploy/images/seapath-vm/seapath-guest-efi-image-seapath-vm.rootfs.wic.qcow2 \
    release-files/seapath-"${VERSION}"-guest-efi-image.rootfs.wic.qcow2
cp build/tmp/deploy/images/seapath-vm/seapath-guest-efi-image-seapath-vm.rootfs.spdx.json \
    release-files/seapath-"${VERSION}"-guest-efi-image.rootfs.spdx.json

# Build seapath-host standalone image
./build.sh -v -i seapath-host-efi-swu-image --distro seapath-standalone-host
cp build/tmp/deploy/images/seapath-hypervisor/seapath-host-efi-image-seapath-hypervisor.rootfs.wic.gz \
    release-files/seapath-"${VERSION}"-host-standalone-efi-image.rootfs.wic.gz
cp build/tmp/deploy/images/seapath-hypervisor/seapath-host-efi-image-seapath-hypervisor.rootfs.wic.bmap \
    release-files/seapath-"${VERSION}"-host-standalone-efi-image.rootfs.wic.bmap
cp build/tmp/deploy/images/seapath-hypervisor/seapath-host-efi-swu-image-seapath-hypervisor.rootfs.swu \
    release-files/seapath-"${VERSION}"-host-standalone-efi-image.rootfs.swu
cp build/tmp/deploy/images/seapath-hypervisor/seapath-host-efi-image-seapath-hypervisor.rootfs.spdx.json \
    release-files/seapath-"${VERSION}"-host-standalone-efi-image.rootfs.spdx.json

# Build seapath-observer image
./build.sh -v -i seapath-observer-efi-swu-image --machine seapath-observer --distro seapath-host
cp build/tmp/deploy/images/seapath-observer/seapath-observer-efi-image-seapath-observer.rootfs.wic.gz \
    release-files/seapath-"${VERSION}"-observer-efi-image.rootfs.wic.gz
cp build/tmp/deploy/images/seapath-observer/seapath-observer-efi-image-seapath-observer.rootfs.wic.bmap \
    release-files/seapath-"${VERSION}"-observer-efi-image.rootfs.wic.bmap
cp build/tmp/deploy/images/seapath-observer/seapath-observer-efi-swu-image-seapath-observer.rootfs.swu \
    release-files/seapath-"${VERSION}"-observer-efi-image.rootfs.swu
cp build/tmp/deploy/images/seapath-observer/seapath-observer-efi-image-seapath-observer.rootfs.spdx.json \
    release-files/seapath-"${VERSION}"-observer-efi-image.rootfs.spdx.json


if [ "$FULL_BUILD" = true ]; then
    # Build seapath-host minimal image
    ./build.sh -v -i seapath-host-efi-image --distro seapath-host-minimal

    # Build seapath-host debug image
    ./build.sh -v -i seapath-host-efi-dbg-image --distro seapath-host

    # Build seapath-host standalone debug image
    ./build.sh -v -i seapath-host-efi-dbg-image --distro seapath-standalone-host

    # Build seapath-guest debug image
    ./build.sh -v -i seapath-guest-efi-dbg-image --distro seapath-guest --machine seapath-vm

    # Build host image with cockpit enabled
    sed -i "s/SEAPATH_COCKPIT='false'/SEAPATH_COCKPIT='true'/" seapath.conf
    ./build.sh -v -i seapath-host-efi-image --distro seapath-host
fi
