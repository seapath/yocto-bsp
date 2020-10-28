#!/bin/bash
# Copyright (C) 2020, RTE (http://www.rte-france.com)
# SPDX-License-Identifier: Apache-2.0

set -e
UUID=$(uuidgen)
OSD_SECRET=$(ceph-authtool --gen-print-key)
if [ $(hostname) = votp1 ] ; then
    ID=0
else
    ID=1
fi
echo "{\"cephx_secret\": \"$OSD_SECRET\"}" | \
   ceph osd new $UUID $ID -i - \
   -n client.bootstrap-osd -k /var/lib/ceph/bootstrap-osd/ceph.keyring \
   >/dev/null 2>/dev/null
mkdir /var/lib/ceph/osd/ceph-${ID} -p
ceph-authtool --create-keyring /var/lib/ceph/osd/ceph-$ID/keyring \
    --name osd.$ID --add-key $OSD_SECRET >/dev/null 2>/dev/null
ceph-osd -i $ID --mkfs --osd-uuid $UUID >/dev/null 2>/dev/null
systemctl start ceph-osd@${ID} >/dev/null 2>/dev/null
systemctl enable ceph-osd@${ID} >/dev/null 2>/dev/null
