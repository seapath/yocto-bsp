#!/bin/bash
# Copyright (C) 2020, RTE (http://www.rte-france.com)
# This program is distributed under the Apache 2 license.

set -e
ceph auth get-or-create client.libvirt \
    mon 'allow r, allow command "osd blacklist"' \
    osd 'allow class-read object_prefix rbd_children, allow rwx pool=rbd' \
    >/dev/null
virsh secret-define --file /opt/setup/secret.xml >/dev/null
ceph auth get-key client.libvirt > /tmp/client.libvirt.key
virsh secret-set-value --secret "07d471ff-5fe3-4b4e-849f-bcc4bb37a7d9" \
    --base64 "$(cat /tmp/client.libvirt.key)" >/dev/null
rm -f /tmp/client.libvirt.key
