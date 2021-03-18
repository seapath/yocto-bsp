#!/bin/bash
# Copyright (C) 2021, RTE (http://www.rte-france.com)
# SPDX-License-Identifier: Apache-2.0

help() { echo "Usage: $0 [files to add] > /path/to/output/file" 1>&2; exit 1; }

if [ $1 = "-h" ]; then help; fi

echo "Name Arch Version Image"

for f in $@; do
  IMAGE=${f%%.*}
  IMAGE=${IMAGE%-*}

  sed -e "s/$/ $IMAGE/" $f
done
