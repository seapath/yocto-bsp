# Copyright (C) 2020, RTE (http://www.rte-france.com)
# SPDX-License-Identifier: Apache-2.0

# Replace jocker value file
replace()
{
    sed "s|@${1}@|${2}|g" -i "${3}"
}

update_ceph_conf_after_setup()
{
    ceph mon enable-msgr2
    sed "s/\bmon host = .*\b/&,${SEAPATH2_ADDR},${OBSERVER_ADDR}/" \
        -i /etc/ceph/ceph.conf
    sed 's/\bmon initial members = seapath1\b/&,seapath2,observer/' \
        -i /etc/ceph/ceph.conf
}
