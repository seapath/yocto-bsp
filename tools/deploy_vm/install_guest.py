from utils import send_ssh_cmd
from utils import copy_file_from, copy_file_into
from utils import run_cmd
import os
import threading
import time


class HostInstaller:
    def __init__(self, host_config, output):
        self.host_config = host_config
        self._host_tmp_dir = None
        self._list_vm_config = []
        self._ip = self.host_config["ip"]
        self._username = self.host_config.get("username", None)
        self._create_tmp_dir()
        self.output_dir = output

    def _create_tmp_dir(self):

        ret = send_ssh_cmd(ip=self._ip, cmd="mktemp -d", user=self._username)
        self._host_tmp_dir = ret.stdout.decode().rstrip()

    def add_vm_configs(self, list_config):
        for config in list_config:
            self._list_vm_config.append(
                VmConfig(
                    config=config,
                    host_ip=self._ip,
                    host_user=self._username,
                    host_tmp_dir=self._host_tmp_dir,
                )
            )

    def _run_simultaneous(self, list_cmd):
        threads = list()
        for c in list_cmd:
            x = threading.Thread(target=c)
            threads.append(x)
            x.start()

        for index, thread in enumerate(threads):
            thread.join()

    def install_all_vms(self):
        self._run_simultaneous([vm_config.run for vm_config in self._list_vm_config])
        print("installation done")

    def destroy_all_vms(self):
        self._run_simultaneous(
            [vm_config.destroy for vm_config in self._list_vm_config]
        )
        print("destroy done")

    def run_all_tests(self, list_test):
        list_guest = []
        print("running all tests")
        for test in list_test:
            guest = [g for g in self._list_vm_config if g.name == test["guest"]]
            if len(guest) != 1:
                raise ValueError("no guest found for test {}".format(test.name))
            test["output_dir"] = os.path.join(
                guest[0]._vm_tmp_dir, test.get("output_name")
            )
            guest[0].cmd = test.get("cmd") + ">" + test.get("output_dir")
            list_guest.append(guest[0])

        self._run_simultaneous([g.run_test for g in list_guest])
        print("tests done")

    def download_all_results(self, list_test):
        for test in list_test:
            copy_file_from(
                self._ip, test.get("output_dir"), self.output_dir, user=self._username
            )


class VmConfig:
    def __init__(self, config, host_ip, host_user, host_tmp_dir):
        self._host_ip = host_ip
        self._host_user = host_user
        for k in config.keys():
            setattr(self, k, config[k])
        self._vm_tmp_dir = os.path.join(host_tmp_dir, self.name)
        self._test_res_dir = os.path.join(self._vm_tmp_dir, "results")

    def destroy(self):
        print("# Destroy {}".format(self.name))
        cmd_shutdown = "virsh shutdown {}".format(self.name)
        cmd_destroy = "virsh destroy {}".format(self.name)
        cmd_delete = "virsh undefine {}".format(self.name)
        cmd_rm = "rm -rf --preserve-root --one-file-system -- {}".format(self._vm_tmp_dir)
        send_ssh_cmd(ip=self._host_ip, cmd=cmd_shutdown, user=self._host_user)
        send_ssh_cmd(ip=self._host_ip, cmd=cmd_destroy, user=self._host_user)
        send_ssh_cmd(ip=self._host_ip, cmd=cmd_delete, user=self._host_user)
        send_ssh_cmd(ip=self._host_ip, cmd=cmd_rm, user=self._host_user)

    def dump(self):
        attrs = vars(self)
        print(", ".join("%s: %s" % item for item in attrs.items()))

    def install(self):
        print("# Install {}".format(self.name))
        run_cmd(self._gen_virt_install_params())

    def prepare(self):
        print("# Prepare {}".format(self.name))
        send_ssh_cmd(
            ip=self._host_ip,
            cmd="mkdir -p {}".format(self._vm_tmp_dir),
            user=self._host_user,
        )
        self._copy_kernel()
        self._copy_rootfs()

    def run(self):
        self.prepare()
        self.install()
        time.sleep(20)
        self.update_ip()

    def run_test(self):
        print("# Run test {}".format(self.cmd))
        cmd_test = "ssh -y root@" + self.ip_addr + " " + self.cmd
        send_ssh_cmd(ip=self._host_ip, cmd=cmd_test, user=self._host_user)

    def update_ip(self):
        print("# Get IP of {}".format(self.name))
        cmd_mac = (
            "virsh dumpxml "
            + self.name
            + " | grep -i 'mac address' | cut -d \"'\" -f 2"
        )
        ret = send_ssh_cmd(ip=self._host_ip, cmd=cmd_mac, user=self._host_user)
        self.mac_addr = ret.stdout.decode().rstrip()

        if not self.mac_addr:
            raise ValueError("no mac address found for {}".format(self.name))

        cmd_ip = (
            "virsh net-dhcp-leases default --mac "
            + self.mac_addr
            + "| awk 'NR>2 { if (NF>0) { print $5 }}' | cut -d \"/\" -f 1"
        )
        ret = send_ssh_cmd(ip=self._host_ip, cmd=cmd_ip, user=self._host_user)
        self.ip_addr = ret.stdout.decode().rstrip()

        if not self.ip_addr:
            raise ValueError("no ip address found for {}".format(self.name))

    def _copy_kernel(self):
        self.dst_kernel_img = os.path.join(
            self._vm_tmp_dir, os.path.split(self.kernel_img)[1]
        )
        copy_file_into(
            ip=self._host_ip,
            file_path=self.kernel_img,
            dst_path=self.dst_kernel_img,
            user=self._host_user,
        )

    def _copy_rootfs(self):
        self.dst_rootfs_img = os.path.join(
            self._vm_tmp_dir, os.path.split(self.rootfs_img)[1]
        )
        copy_file_into(
            ip=self._host_ip,
            file_path=self.rootfs_img,
            dst_path=self.dst_rootfs_img,
            user=self._host_user,
        )

    def _gen_virt_install_params(self):

        cmd = [
            "virt-install",
            "--connect",
            "qemu+ssh://root@" + self._host_ip + "/system",
            "--name",
            self.name,
            "--memory",
            str(self.memory),
            "--boot",
            "kernel="
            + self.dst_kernel_img
            + ',kernel_args="console=ttyS0 root=/dev/sda"',
            "--disk",
            self.dst_rootfs_img,
            "--graphics",
            "none",
            "--network",
            "bridge=virbr0,model=virtio",
            "--noautoconsole",
        ]

        if getattr(self, "cpuset", None):
            cmd.append("--cpuset=" + str(self.cpuset))

        return cmd
