#!/bin/bash
# Copyright (C) 2020, RTE (http://www.rte-france.com)
# SPDX-License-Identifier: Apache-2.0


source_dir=$(dirname "$0")
source "${source_dir}"/src/utils.sh

# params disk
check_rbd_disk_present()
{
    if run_ssh_command seapath1 rbd list | grep -q -E "^${1}$" ; then
        echo yes
    else
        echo no
    fi
}

usage()
{
    echo 'usage: import_vm_disk.sh [-h] [--name remote_name] [--force] image'
    echo
    echo 'positional arguments:'
    echo '  image                     image file path'
    echo
    echo 'optional arguments:'
    echo '  -h, --help                show this help message and exit'
    echo '  -n, --name remote_name    the remote file name (default disk)'
    echo '  -f, --force,              erease remote disk if already present'
}

force=
disk_file=
disk_name=disk

options=$(getopt -o hfn: --long force,name:,help -- "$@")
[ $? -eq 0 ] || {
    echo "Incorrect options provided"
    exit 1
}

eval set -- "$options"
while true; do
    case "$1" in
    -f|--force)
        force=yes
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    -n|--name)
        shift
        disk_name="$1"
        ;;
    --)
        shift
        break
        ;;
    esac
    shift
done

disk_file="$1"

if [ -z "${disk_file}" ] ; then
    echo "Invalid argument" 2>&1
    usage
    exit 1
fi

if [ ! -f "${disk_file}" ] ; then
    echo "File not found ${disk_file}"
    exit 1
fi

if [ $(check_rbd_disk_present "$disk_name") = yes ] ; then
    if [ -z "$force" ] ; then
        echo "Error $disk_name already imported"
        exit 1
    else
        run_ssh_command seapath1 rbd "rm '${disk_name}'"
    fi
fi

echo "Uploading ${disk_file}"
scp ${SSH_OPTIONS} "${disk_file}" root@"${SEAPATH1_ADDR}":/var/"${disk_name}"
run_ssh_command seapath1 rbd "import /var/'${disk_name}'"
run_ssh_command seapath1 rm "-f /var/'${disk_name}'"
