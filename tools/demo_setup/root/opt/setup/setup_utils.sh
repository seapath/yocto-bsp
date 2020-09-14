# Replace jocker value file
replace()
{
    sed "s|@${1}@|${2}|g" -i "${3}"
}

update_ceph_conf_after_setup()
{
    ceph mon enable-msgr2
    sed "s/\bmon host = .*\b/&,${VOTP2_ADDR},${OBSERVER_ADDR}/" \
        -i /etc/ceph/ceph.conf
    sed 's/\bmon initial members = votp1\b/&,votp2,observer/' \
        -i /etc/ceph/ceph.conf
}
