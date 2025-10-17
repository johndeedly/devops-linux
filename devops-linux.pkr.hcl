packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1"
    }
    virtualbox = {
      source  = "github.com/hashicorp/virtualbox"
      version = "~> 1"
    }
  }
}


variable "cpu_cores" {
  type    = number
  default = 4
}

variable "memory" {
  type    = number
  default = 4096
}

variable "headless" {
  type    = bool
  default = true
}

variable "package_manager" {
  type    = string
  default = "pacman"
}

variable "package_cache" {
  type    = bool
  default = false
}

locals {
  build_name_qemu       = join(".", ["devops-linux-x86_64", replace(timestamp(), ":", "꞉"), "qcow2"]) # unicode replacement char for colon
  build_name_virtualbox = join(".", ["devops-linux-x86_64", replace(timestamp(), ":", "꞉")]) # unicode replacement char for colon
  ovmf_code_arch        = "/usr/share/OVMF/x64/OVMF_CODE.secboot.4m.fd"
  ovmf_code_debian      = "/usr/share/OVMF/OVMF_CODE_4M.secboot.fd"
  ovmf_vars_arch        = "/usr/share/OVMF/x64/OVMF_VARS.4m.fd"
  ovmf_vars_debian      = "/usr/share/OVMF/OVMF_VARS_4M.fd"
  has_ovmf_code_arch    = fileexists(local.ovmf_code_arch)
  has_ovmf_code_debian  = fileexists(local.ovmf_code_debian)
  has_ovmf_vars_arch    = fileexists(local.ovmf_vars_arch)
  has_ovmf_vars_debian  = fileexists(local.ovmf_vars_debian)
  can_efi_boot          = local.has_ovmf_code_arch ? true : local.has_ovmf_code_debian ? true : false
  efi_firmware_code     = local.has_ovmf_code_arch ? local.ovmf_code_arch : local.has_ovmf_code_debian ? local.ovmf_code_debian : null
  efi_firmware_vars     = local.has_ovmf_vars_arch ? local.ovmf_vars_arch : local.has_ovmf_vars_debian ? local.ovmf_vars_debian : null
}


source "qemu" "default" {
  boot_wait            = "3s"
  boot_command         = ["<enter>"]
  disk_size            = "524288M"
  memory               = var.memory
  format               = "qcow2"
  accelerator          = "kvm"
  disk_discard         = "unmap"
  disk_detect_zeroes   = "unmap"
  disk_interface       = "virtio"
  disk_compression     = false
  skip_compaction      = true
  net_device           = "virtio-net"
  vga                  = "virtio"
  machine_type         = "q35"
  cpu_model            = "host"
  efi_boot             = local.can_efi_boot
  efi_firmware_code    = local.efi_firmware_code
  efi_firmware_vars    = local.efi_firmware_vars
  sockets              = 1
  cores                = var.cpu_cores
  threads              = 1
  qemuargs             = [
    ["-virtfs", "local,path=./database,mount_tag=database.0,security_model=mapped,id=database.0"],
    ["-rtc", "base=utc,clock=host"],
    ["-device", "virtio-tablet"],
    ["-device", "virtio-keyboard"]
  ]
  headless             = var.headless
  iso_checksum         = "none"
  iso_url              = "devops-x86_64-cidata.iso"
  output_directory     = "output/devops-linux"
  ssh_username         = "root"
  ssh_keypair_name     = "ssh_packer_key"
  ssh_private_key_file = "./ssh_packer_key"
  ssh_timeout          = "10m"
  vm_name              = local.build_name_qemu
}


source "virtualbox-iso" "default" {
  acpi_shutdown            = true
  boot_wait                = "3s"
  boot_command             = ["<enter>"]
  disk_size                = 524288
  memory                   = var.memory
  format                   = "ova"
  guest_additions_mode     = "disable"
  guest_os_type            = "Linux_64"
  hard_drive_discard       = true
  hard_drive_interface     = "virtio"
  hard_drive_nonrotational = true
  chipset                  = "ich9"
  firmware                 = "efi"
  cpus                     = var.cpu_cores
  usb                      = true
  nic_type                 = "virtio"
  gfx_controller           = "vboxsvga"
  gfx_accelerate_3d        = true
  gfx_vram_size            = 64
  headless                 = var.headless
  iso_checksum             = "none"
  iso_interface            = "virtio"
  iso_url                  = "devops-x86_64-cidata.iso"
  output_directory         = "output/devops-linux"
  output_filename          = "devops-linux-x86_64"
  ssh_username             = "root"
  ssh_keypair_name         = "ssh_packer_key"
  ssh_private_key_file     = "./ssh_packer_key"
  ssh_timeout              = "10m"
  vboxmanage               = [["modifyvm", "{{ .Name }}", "--audio-out", "on", "--audio-enabled", "on", "--usb-xhci", "on", "--clipboard", "hosttoguest", "--draganddrop", "hosttoguest", "--acpi", "on", "--ioapic", "on", "--apic", "on", "--pae", "on", "--nested-hw-virt", "on", "--paravirtprovider", "kvm", "--hpet", "on", "--hwvirtex", "on", "--largepages", "on", "--vtxvpid", "on", "--vtxux", "on", "--biosbootmenu", "messageandmenu", "--rtcuseutc", "on", "--macaddress1", "auto"], ["sharedfolder", "add", "{{ .Name }}", "--name", "database.0", "--hostpath", "./database"]]
  vboxmanage_post          = [["modifyvm", "{{ .Name }}", "--macaddress1", "auto"], ["sharedfolder", "remove", "{{ .Name }}", "--name", "database.0"]]
  vm_name                  = local.build_name_virtualbox
  skip_export              = false
  keep_registered          = true
}


build {
  sources = ["source.qemu.default", "source.virtualbox-iso.default"]

  provisioner "shell" {
    inline           = [<<EOS
( until [ "SubState=active" = "$(systemctl show cloud-init.target -p SubState)" ]; do sleep 5; done ) &
pid=$!
tail --pid=$pid -f /cidata_log
EOS
    ]
    valid_exit_codes = [0, 2]
  }

  provisioner "file" {
    source      = "/cidata_log"
    destination = "output/devops-linux-cidata.log"
    direction   = "download"
  }

  provisioner "shell" {
    expect_disconnect = true
    inline            = [<<EOS
echo "[ OK ] Rebooting the system"
VMLINUZ=$(find /boot -maxdepth 1 -name 'vmlinuz*' | sort -Vru | head -n1)
INITRD=$(find /boot -maxdepth 1 \( \( -name 'initramfs-linux*' -a ! -name '*fallback*' -a ! -name '*pxe*' \) -o -name 'initrd*' \) | sort -Vru | head -n1)
PROC_ROOT=$(sed -ne 's/.*\(root=[^ $]*\).*/\1/p' /proc/cmdline)
GRUB_CMDLINE=$(sed -ne 's/^GRUB_CMDLINE_LINUX_DEFAULT="\([^"]*\)"/\1/p' /etc/default/grub)
if [ -n "$VMLINUZ" ] && [ -e "$VMLINUZ" ] && [ -n "$INITRD" ] && [ -e "$INITRD" ]; then
  echo "[ OK ] Found next kernel '$VMLINUZ' and initramfs '$INITRD'"
  kexec -l "$VMLINUZ" --initrd="$INITRD" --append="$PROC_ROOT $GRUB_CMDLINE"
  for gpumod in amdgpu radeon nouveau i915 virtio-gpu vmwgfx; do
    modprobe -r "$gpumod" || true
  done
  echo "[ OK ] kexec now"
  systemctl kexec
else
  reboot now
fi
EOS
    ]
    pause_after       = "20s"
  }
  
  provisioner "shell" {
    inline           = [<<EOS
( until [ "SubState=active" = "$(systemctl show cloud-init.target -p SubState)" ]; do sleep 5; done ) &
pid=$!
tail --pid=$pid -f /cidata_log
EOS
    ]
    valid_exit_codes = [0, 2]
  }

  provisioner "file" {
    source      = "/cidata_log"
    destination = "output/devops-linux-cidata.log"
    direction   = "download"
  }

  provisioner "file" {
    source      = var.package_cache ? "/var/cache/${var.package_manager}/" : ""
    destination = "database/stage"
    direction   = "download"
  }

  provisioner "shell" {
    inline = ["mkdir -p /srv/pxe /srv/docker /srv/liveiso /srv/tar /srv/audit"]
  }

  provisioner "file" {
    source      = "/srv/pxe/"
    destination = "output/artifacts"
    direction   = "download"
  }

  provisioner "file" {
    source      = "/srv/docker/"
    destination = "output/artifacts"
    direction   = "download"
  }

  provisioner "file" {
    source      = "/srv/liveiso/"
    destination = "output/artifacts"
    direction   = "download"
  }

  provisioner "file" {
    source      = "/srv/tar/"
    destination = "output/artifacts"
    direction   = "download"
  }

  provisioner "file" {
    source      = "/srv/audit/"
    destination = "output/artifacts"
    direction   = "download"
  }

  provisioner "shell-local" {
    inline = [<<EOS
tee output/devops-linux/devops-linux-x86_64.run.sh <<EOF
#!/usr/bin/env bash
trap "trap - SIGTERM && kill -- -\$\$" SIGINT SIGTERM EXIT
if [ -f "${local.ovmf_code_arch}" ] || [ -f "${local.ovmf_code_debian}" ]; then
/usr/bin/qemu-system-x86_64 \\
  -name devops-linux-x86_64 \\
  -machine type=q35,accel=kvm \\
  -device virtio-vga,id=video.0,max_outputs=1,hostmem=64M \\
  -vga none \\
  -display gtk,gl=on,show-cursor=on,zoom-to-fit=off \\
  -cpu host \\
  -drive file=${local.build_name_qemu},if=virtio,cache=writeback,discard=unmap,detect-zeroes=unmap,format=qcow2 \\
  -drive file=${local.efi_firmware_code},if=pflash,unit=0,format=raw,readonly=on \\
  -drive file=efivars.fd,if=pflash,unit=1,format=raw \\
  -smp ${var.cpu_cores},sockets=1,cores=${var.cpu_cores},maxcpus=${var.cpu_cores} -m ${var.memory}M \\
  -netdev user,id=user.0,hostfwd=tcp::9091-:9090 -device virtio-net,netdev=user.0 \\
  -audio driver=pa,model=hda,id=snd0 -device hda-output,audiodev=snd0 \\
  -device virtio-tablet -device virtio-keyboard \\
  -rtc base=utc,clock=host \\
  -virtfs local,path=../artifacts,mount_tag=artifacts.0,security_model=passthrough,id=artifacts.0
else
/usr/bin/qemu-system-x86_64 \\
  -name devops-linux-x86_64 \\
  -machine type=q35,accel=kvm \\
  -device virtio-vga,id=video.0,max_outputs=1,hostmem=64M \\
  -vga none \\
  -display gtk,gl=on,show-cursor=on,zoom-to-fit=off \\
  -cpu host \\
  -drive file=${local.build_name_qemu},if=virtio,cache=writeback,discard=unmap,detect-zeroes=unmap,format=qcow2 \\
  -smp ${var.cpu_cores},sockets=1,cores=${var.cpu_cores},maxcpus=${var.cpu_cores} -m ${var.memory}M \\
  -netdev user,id=user.0,hostfwd=tcp::9091-:9090 -device virtio-net,netdev=user.0 \\
  -audio driver=pa,model=hda,id=snd0 -device hda-output,audiodev=snd0 \\
  -device virtio-tablet -device virtio-keyboard \\
  -rtc base=utc,clock=host \\
  -virtfs local,path=../artifacts,mount_tag=artifacts.0,security_model=passthrough,id=artifacts.0
fi

# /usr/bin/swtpm socket --tpm2 --tpmstate dir="..." --ctrl type=unixio,path=".../vtpm.sock"
# -device tpm-tis,tpmdev=tpm0 -tpmdev emulator,id=tpm0,chardev=vtpm -chardev "socket,id=vtpm,path=.../vtpm.sock"
EOF
chmod +x output/devops-linux/devops-linux-x86_64.run.sh
tee output/devops-linux/devops-linux-x86_64.gl.sh <<EOF
#!/usr/bin/env bash
trap "trap - SIGTERM && kill -- -\$\$" SIGINT SIGTERM EXIT
if [ -f "${local.ovmf_code_arch}" ] || [ -f "${local.ovmf_code_debian}" ]; then
/usr/bin/qemu-system-x86_64 \\
  -name devops-linux-x86_64 \\
  -machine type=q35,accel=kvm \\
  -device virtio-vga-gl,id=video.0,max_outputs=1,hostmem=64M \\
  -vga none \\
  -display gtk,gl=on,show-cursor=on,zoom-to-fit=off \\
  -cpu host \\
  -drive file=${local.build_name_qemu},if=virtio,cache=writeback,discard=unmap,detect-zeroes=unmap,format=qcow2 \\
  -drive file=${local.efi_firmware_code},if=pflash,unit=0,format=raw,readonly=on \\
  -drive file=efivars.fd,if=pflash,unit=1,format=raw \\
  -smp ${var.cpu_cores},sockets=1,cores=${var.cpu_cores},maxcpus=${var.cpu_cores} -m ${var.memory}M \\
  -netdev user,id=user.0,hostfwd=tcp::9091-:9090 -device virtio-net,netdev=user.0 \\
  -audio driver=pa,model=hda,id=snd0 -device hda-output,audiodev=snd0 \\
  -device virtio-tablet -device virtio-keyboard \\
  -rtc base=utc,clock=host \\
  -virtfs local,path=../artifacts,mount_tag=artifacts.0,security_model=passthrough,id=artifacts.0
else
/usr/bin/qemu-system-x86_64 \\
  -name devops-linux-x86_64 \\
  -machine type=q35,accel=kvm \\
  -device virtio-vga-gl,id=video.0,max_outputs=1,hostmem=64M \\
  -vga none \\
  -display gtk,gl=on,show-cursor=on,zoom-to-fit=off \\
  -cpu host \\
  -drive file=${local.build_name_qemu},if=virtio,cache=writeback,discard=unmap,detect-zeroes=unmap,format=qcow2 \\
  -smp ${var.cpu_cores},sockets=1,cores=${var.cpu_cores},maxcpus=${var.cpu_cores} -m ${var.memory}M \\
  -netdev user,id=user.0,hostfwd=tcp::9091-:9090 -device virtio-net,netdev=user.0 \\
  -audio driver=pa,model=hda,id=snd0 -device hda-output,audiodev=snd0 \\
  -device virtio-tablet -device virtio-keyboard \\
  -rtc base=utc,clock=host \\
  -virtfs local,path=../artifacts,mount_tag=artifacts.0,security_model=passthrough,id=artifacts.0
fi

# /usr/bin/swtpm socket --tpm2 --tpmstate dir="..." --ctrl type=unixio,path=".../vtpm.sock"
# -device tpm-tis,tpmdev=tpm0 -tpmdev emulator,id=tpm0,chardev=vtpm -chardev "socket,id=vtpm,path=.../vtpm.sock"
EOF
chmod +x output/devops-linux/devops-linux-x86_64.gl.sh
tee output/devops-linux/devops-linux-x86_64.pxe.sh <<EOF
#!/usr/bin/env bash
trap "trap - SIGTERM && kill -- -\$\$" SIGINT SIGTERM EXIT
/usr/bin/qemu-system-x86_64 \\
  -name devops-linux-pxe-x86_64 \\
  -machine type=q35,accel=kvm \\
  -device virtio-vga,id=video.0,max_outputs=1,hostmem=64M \\
  -vga none \\
  -display gtk,gl=on,show-cursor=on,zoom-to-fit=off \\
  -cpu host \\
  -smp ${var.cpu_cores},sockets=1,cores=${var.cpu_cores},maxcpus=${var.cpu_cores} -m ${var.memory}M \\
  -netdev socket,id=user.0,connect=:23568 -device virtio-net,netdev=user.0 \\
  -audio driver=pa,model=hda,id=snd0 -device hda-output,audiodev=snd0 \\
  -device virtio-tablet -device virtio-keyboard \\
  -rtc base=utc,clock=host

# remove -display gtk,gl=on for no 3d acceleration
# -display none, -daemonize, hostfwd=::12457-:22 for running as a daemonized server
EOF
chmod +x output/devops-linux/devops-linux-x86_64.pxe.sh
tee output/devops-linux/devops-linux-x86_64.netdev.sh <<EOF
#!/usr/bin/env bash
trap "trap - SIGTERM && kill -- -\$\$" SIGINT SIGTERM EXIT
if [ -f "${local.ovmf_code_arch}" ] || [ -f "${local.ovmf_code_debian}" ]; then
/usr/bin/qemu-system-x86_64 \\
  -name devops-linux-x86_64 \\
  -machine type=q35,accel=kvm \\
  -device virtio-vga,id=video.0,max_outputs=1,hostmem=64M \\
  -vga none \\
  -display gtk,gl=on,show-cursor=on,zoom-to-fit=off \\
  -cpu host \\
  -drive file=${local.build_name_qemu},if=virtio,cache=writeback,discard=unmap,detect-zeroes=unmap,format=qcow2 \\
  -drive file=${local.efi_firmware_code},if=pflash,unit=0,format=raw,readonly=on \\
  -drive file=efivars.fd,if=pflash,unit=1,format=raw \\
  -smp ${var.cpu_cores},sockets=1,cores=${var.cpu_cores},maxcpus=${var.cpu_cores} -m ${var.memory}M \\
  -netdev user,id=user.0,hostfwd=tcp::9091-:9090 -device virtio-net,netdev=user.0 \\
  -netdev socket,id=user.1,listen=:23568 -device virtio-net,netdev=user.1 \\
  -audio driver=pa,model=hda,id=snd0 -device hda-output,audiodev=snd0 \\
  -device virtio-tablet -device virtio-keyboard \\
  -rtc base=utc,clock=host \\
  -virtfs local,path=../artifacts,mount_tag=artifacts.0,security_model=passthrough,id=artifacts.0
else
/usr/bin/qemu-system-x86_64 \\
  -name devops-linux-x86_64 \\
  -machine type=q35,accel=kvm \\
  -device virtio-vga,id=video.0,max_outputs=1,hostmem=64M \\
  -vga none \\
  -display gtk,gl=on,show-cursor=on,zoom-to-fit=off \\
  -cpu host \\
  -drive file=${local.build_name_qemu},if=virtio,cache=writeback,discard=unmap,detect-zeroes=unmap,format=qcow2 \\
  -smp ${var.cpu_cores},sockets=1,cores=${var.cpu_cores},maxcpus=${var.cpu_cores} -m ${var.memory}M \\
  -netdev user,id=user.0,hostfwd=tcp::9091-:9090 -device virtio-net,netdev=user.0 \\
  -netdev socket,id=user.1,listen=:23568 -device virtio-net,netdev=user.1 \\
  -audio driver=pa,model=hda,id=snd0 -device hda-output,audiodev=snd0 \\
  -device virtio-tablet -device virtio-keyboard \\
  -rtc base=utc,clock=host \\
  -virtfs local,path=../artifacts,mount_tag=artifacts.0,security_model=passthrough,id=artifacts.0
fi

# /usr/bin/swtpm socket --tpm2 --tpmstate dir="..." --ctrl type=unixio,path=".../vtpm.sock"
# -device tpm-tis,tpmdev=tpm0 -tpmdev emulator,id=tpm0,chardev=vtpm -chardev "socket,id=vtpm,path=.../vtpm.sock"
EOF
chmod +x output/devops-linux/devops-linux-x86_64.netdev.sh
tee output/devops-linux/devops-linux-x86_64.srv.sh <<EOF
#!/usr/bin/env bash
trap "trap - SIGTERM && kill -- -\$\$" SIGINT SIGTERM EXIT
/usr/bin/qemu-system-x86_64 \\
  -name devops-linux-srv-x86_64 \\
  -machine type=q35,accel=kvm \\
  -device virtio-vga,id=video.0,max_outputs=1,hostmem=64M \\
  -vga none \\
  -display none \\
  -cpu host \\
  -smp ${var.cpu_cores},sockets=1,cores=${var.cpu_cores},maxcpus=${var.cpu_cores} -m ${var.memory}M \\
  -netdev user,id=user.0,hostfwd=tcp::8022-:22,hostfwd=tcp::9091-:9090 -device virtio-net,netdev=user.0 \\
  -device virtio-tablet -device virtio-keyboard \\
  -rtc base=utc,clock=host

# -daemonize for running as a daemonized server
EOF
chmod +x output/devops-linux/devops-linux-x86_64.srv.sh
EOS
    ]
    only_on = ["linux"]
  }
  
  provisioner "shell" {
    inline = [<<EOS
echo "[ ## ] Remove provisioning key to lock down ssh"
/bin/sed -i '/packer-provisioning-key/d' /root/.ssh/authorized_keys
echo "[ ## ] Sync disk contents"
sync
EOS
    ]
  }
}
