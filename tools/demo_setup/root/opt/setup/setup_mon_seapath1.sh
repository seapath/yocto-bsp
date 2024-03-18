#!/bin/bash
# Copyright (C) 2020, RTE (http://www.rte-france.com)
# SPDX-License-Identifier: Apache-2.0

set -e

source /opt/setup/setup_config.sh
source /opt/setup/setup_utils.sh

mkdir -p /var/lib/ceph/mon/ceph-seapath1
ceph-authtool --create-keyring /tmp/ceph.mon.keyring --gen-key -n mon. \
    --cap mon 'allow *' >/dev/null 2>/dev/null
ceph-authtool /tmp/ceph.mon.keyring --import-keyring \
    /etc/ceph/ceph.client.admin.keyring >/dev/null 2>/dev/null
ceph-authtool /tmp/ceph.mon.keyring --import-keyring \
    /var/lib/ceph/bootstrap-osd/ceph.keyring >/dev/null 2>/dev/null
monmaptool --create --add seapath1 "${SEAPATH1_ADDR}" \
    --fsid fa7a17d1-5351-459e-bf0e-07e7edc9a625 /tmp/monmap >/dev/null \
    2>/dev/null
ceph-mon --cluster ceph --mkfs -i seapath1 --monmap /tmp/monmap  \
    --keyring /tmp/ceph.mon.keyring >/dev/null 2>/dev/null
systemctl start 'ceph-mon@seapath1' >/dev/null  2>/dev/null
systemctl enable 'ceph-mon@seapath1' >/dev/null  2>/dev/null
update_ceph_conf_after_setup
