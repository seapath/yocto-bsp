#!/bin/bash
# Copyright (C) 2020, RTE (http://www.rte-france.com)
# This program is distributed under the Apache 2 license.

set -e

source /opt/setup/setup_config.sh
source /opt/setup/setup_utils.sh

mkdir -p /var/lib/ceph/mon/ceph-votp2
ceph auth get mon. -o /tmp/myauth >/dev/null 2>/dev/null
ceph mon getmap -o /tmp/monmap >/dev/null 2>/dev/null
ceph-mon -i votp2 --mkfs --monmap /tmp/monmap  --keyring /tmp/myauth \
    >/dev/null 2>/dev/null
systemctl start ceph-mon\@votp2 >/dev/null 2>/dev/null
systemctl enable ceph-mon\@votp2 >/dev/null 2>/dev/null
update_ceph_conf_after_setup
