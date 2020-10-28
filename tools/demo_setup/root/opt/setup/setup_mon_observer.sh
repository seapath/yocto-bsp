#!/bin/bash
# Copyright (C) 2020, RTE (http://www.rte-france.com)
# SPDX-License-Identifier: Apache-2.0

set -e

source /opt/setup/setup_config.sh
source /opt/setup/setup_utils.sh

mkdir -p /var/lib/ceph/mon/ceph-observer
ceph auth get mon. -o /tmp/myauth >/dev/null 2>/dev/null
ceph mon getmap -o /tmp/monmap >/dev/null 2>/dev/null
ceph-mon -i observer --mkfs --monmap /tmp/monmap  --keyring /tmp/myauth >/dev/null
systemctl start 'ceph-mon@observer' >/dev/null 2>/dev/null
systemctl enable 'ceph-mon@observer' >/dev/null 2>/dev/null
update_ceph_conf_after_setup
