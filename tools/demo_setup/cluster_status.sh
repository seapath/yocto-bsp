#!/bin/bash
set -e

source_dir=$(dirname "$0")
source "${source_dir}"/src/utils.sh

if ping -c 1 -W 1  "${VOTP1_ADDR}" 1>/dev/null 2>&1 ; then
    run_ssh_command votp1 crm status
elif ping -c 1 -W 1  "${VOTP2_ADDR}" 1>/dev/null 2>&1 ; then
    run_ssh_command votp2 crm status
else
    echo "Error could not connect to VOTP1 nor VOTP2"
    exit 1
fi
