#!/bin/bash
crm configure property stonith-enabled=false >/dev/null
crm configure property no-quorum-policy=ignore >/dev/null
