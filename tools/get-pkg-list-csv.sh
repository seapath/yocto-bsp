#!/bin/bash
# Copyright (C) 2021, RTE (http://www.rte-france.com)
# SPDX-License-Identifier: Apache-2.0

help() { echo "Usage: $0 [files to add]" 1>&2; exit 1; }

if [ $1 = "-h" ]; then help; fi

OUTFILE="$(date -u +"%Y-%m-%d_%H-%M-%S").csv"
echo "Name Arch Version Image" > $OUTFILE

for f in $@; do
  IMAGE=${f%%.*}
  IMAGE=${IMAGE%-*}

  sed -e "s/$/ $IMAGE/" $f >> $OUTFILE
done
