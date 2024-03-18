#!/bin/bash
# Copyright (C) 2020, RTE (http://www.rte-france.com)
# SPDX-License-Identifier: Apache-2.0

set -e

source_dir=$(dirname "$0")
source "${source_dir}"/src/utils.sh

if ping -c 1 -W 1  "${SEAPATH1_ADDR}" 1>/dev/null 2>&1 ; then
    run_ssh_command seapath1 crm status
elif ping -c 1 -W 1  "${SEAPATH2_ADDR}" 1>/dev/null 2>&1 ; then
    run_ssh_command seapath2 crm status
else
    echo "Error could not connect to SEAPATH1 nor SEAPATH2"
    exit 1
fi
