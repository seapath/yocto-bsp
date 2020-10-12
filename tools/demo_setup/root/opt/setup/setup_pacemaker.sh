#!/bin/bash
# Copyright (C) 2020, RTE (http://www.rte-france.com)
# This program is distributed under the Apache 2 license.

crm configure property stonith-enabled=false >/dev/null
crm configure property no-quorum-policy=ignore >/dev/null
