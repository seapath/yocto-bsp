# Copyright (C) 2020, RTE (http://www.rte-france.com)
# This program is distributed under the Apache 2 license.

import os
import subprocess


def send_ssh_cmd(ip, cmd, user="root"):

    ret = subprocess.run(
        ["ssh", user + "@" + ip, cmd], check=True, stdout=subprocess.PIPE
    )

    return ret


def copy_file_into(ip, file_path, dst_path, user="root"):

    if os.path.isfile(file_path):
        ret = subprocess.run(
            ["scp", file_path, user + "@" + ip + ":" + dst_path],
            check=True,
            stdout=subprocess.PIPE,
        )

    else:
        raise ValueError("{} does not exist".format(file_path))

    return ret


def copy_file_from(ip, file_path, dst_path, user="root"):

    if os.path.isdir(dst_path):
        ret = subprocess.run(
            ["scp", user + "@" + ip + ":" + file_path, dst_path],
            check=True,
            stdout=subprocess.PIPE,
        )

    else:
        raise ValueError("{} does not exist".format(dst_path))

    return ret


def run_cmd(cmd):

    ret = subprocess.run(cmd, check=True, stdout=subprocess.PIPE)

    return ret
