#!/bin/bash
# Copyright (C) 2020, RTE (http://www.rte-france.com)

crm configure property stonith-enabled=false >/dev/null
crm configure property no-quorum-policy=ignore >/dev/null
