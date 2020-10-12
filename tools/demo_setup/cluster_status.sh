#!/bin/bash
# Copyright (C) 2020, RTE (http://www.rte-france.com)
# This program is distributed under the Apache 2 license.

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
