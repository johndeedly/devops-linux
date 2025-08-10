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
}


source "qemu" "default" {
  shutdown_command     = "/sbin/poweroff"
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
  efi_boot             = true
  efi_firmware_code    = "/usr/share/OVMF/x64/OVMF_CODE.secboot.4m.fd"
  efi_firmware_vars    = "/usr/share/OVMF/x64/OVMF_VARS.4m.fd"
  sockets              = 1
  cores                = var.cpu_cores
  threads              = 1
  qemuargs             = [["-rtc", "base=utc,clock=host"], ["-device", "virtio-mouse"], ["-device", "virtio-keyboard"]]
  headless             = var.headless
  iso_checksum         = "none"
  iso_url              = "devops-x86_64-cidata.iso"
  output_directory     = "output/devops-linux"
  ssh_username         = "provisioning"
  ssh_password         = "provisioning-build-passwd"
  ssh_timeout          = "10m"
  vm_name              = local.build_name_qemu
}


source "virtualbox-iso" "default" {
  shutdown_command         = "/sbin/poweroff"
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
  ssh_username             = "provisioning"
  ssh_password             = "provisioning-build-passwd"
  ssh_timeout              = "10m"
  vboxmanage               = [["modifyvm", "{{ .Name }}", "--tpm-type", "2.0", "--audio-out", "on", "--audio-enabled", "on", "--usb-xhci", "on", "--clipboard", "hosttoguest", "--draganddrop", "hosttoguest", "--acpi", "on", "--ioapic", "on", "--apic", "on", "--pae", "on", "--nested-hw-virt", "on", "--paravirtprovider", "kvm", "--hpet", "on", "--hwvirtex", "on", "--largepages", "on", "--vtxvpid", "on", "--vtxux", "on", "--biosbootmenu", "messageandmenu", "--rtcuseutc", "on", "--macaddress1", "auto"]]
  vboxmanage_post          = [["modifyvm", "{{ .Name }}", "--macaddress1", "auto"]]
  vm_name                  = local.build_name_virtualbox
  skip_export              = false
  keep_registered          = true
}


build {
  sources = ["source.qemu.default", "source.virtualbox-iso.default"]

  provisioner "shell" {
    execute_command  = "tail -f /cidata_log & trap 'kill -- -$$' EXIT; chmod +x {{ .Path }}; {{ .Vars }} {{ .Path }}"
    inline           = ["until [ -f /run/cloud-init/result.json ]; do sleep 3; done"]
    valid_exit_codes = [0, 143]
  }

  provisioner "shell" {
    inline           = [
      "cloud-init status",
      "rc=$?",
      "[ $rc -eq 1 ] && cloud-init status --long --format yaml",
      "exit $rc"
    ]
    valid_exit_codes = [0, 2]
  }

  provisioner "file" {
    source      = "/cidata_log"
    destination = "output/devops-linux-cidata.log"
    direction   = "download"
  }

  provisioner "file" {
    source      = var.package_cache ? "/var/cache/pacman/pkg/" : ""
    destination = "database/archiso"
    direction   = "download"
  }

  provisioner "shell" {
    expect_disconnect = true
    inline            = [
      "reboot now",
    ]
    pause_after       = "5s"
  }
  
  provisioner "shell" {
    pause_before     = "5s"
    execute_command  = "tail -f /cidata_log & trap 'kill -- -$$' EXIT; chmod +x {{ .Path }}; {{ .Vars }} {{ .Path }}"
    inline           = ["until [ -f /run/cloud-init/result.json ]; do sleep 3; done"]
    valid_exit_codes = [0, 143]
  }

  provisioner "shell" {
    inline           = [
      "cloud-init status",
      "rc=$?",
      "[ $rc -eq 1 ] && cloud-init status --long --format yaml",
      "exit $rc"
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
    inline            = [
      "reboot now",
    ]
    pause_after       = "5s"
  }
  
  provisioner "shell" {
    pause_before     = "5s"
    execute_command  = "tail -f /cidata_log & trap 'kill -- -$$' EXIT; chmod +x {{ .Path }}; {{ .Vars }} {{ .Path }}"
    inline           = ["until [ -f /run/cloud-init/result.json ]; do sleep 3; done"]
    valid_exit_codes = [0, 143]
  }

  provisioner "shell" {
    inline           = [
      "cloud-init status",
      "rc=$?",
      "[ $rc -eq 1 ] && cloud-init status --long --format yaml",
      "exit $rc"
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
/usr/bin/qemu-system-x86_64 \\
  -name devops-linux-x86_64 \\
  -machine type=q35,accel=kvm \\
  -device virtio-vga,id=video.0,max_outputs=1,hostmem=64M \\
  -vga none \\
  -display gtk,gl=on,show-cursor=on,zoom-to-fit=off \\
  -cpu host \\
  -drive file=${local.build_name_qemu},if=virtio,cache=writeback,discard=unmap,detect-zeroes=unmap,format=qcow2 \\
  -drive file=/usr/share/OVMF/x64/OVMF_CODE.secboot.4m.fd,if=pflash,unit=0,format=raw,readonly=on \\
  -drive file=efivars.fd,if=pflash,unit=1,format=raw \\
  -smp ${var.cpu_cores},sockets=1,cores=${var.cpu_cores},maxcpus=${var.cpu_cores} -m ${var.memory}M \\
  -netdev user,id=user.0,hostfwd=tcp::9091-:9090 -device virtio-net,netdev=user.0 \\
  -audio driver=pa,model=hda,id=snd0 -device hda-output,audiodev=snd0 \\
  -device virtio-mouse -device virtio-keyboard \\
  -rtc base=utc,clock=host \\
  -virtfs local,path=../artifacts,mount_tag=artifacts.0,security_model=passthrough,id=artifacts.0

# /usr/bin/swtpm socket --tpm2 --tpmstate dir="..." --ctrl type=unixio,path=".../vtpm.sock"
# -device tpm-tis,tpmdev=tpm0 -tpmdev emulator,id=tpm0,chardev=vtpm -chardev "socket,id=vtpm,path=.../vtpm.sock"

# -netdev user,id=user.0,[...]
# -netdev socket,id=user.1,listen=:23568 -device virtio-net,netdev=user.1
EOF
chmod +x output/devops-linux/devops-linux-x86_64.run.sh
tee output/devops-linux/devops-linux-x86_64.gl.sh <<EOF
#!/usr/bin/env bash
trap "trap - SIGTERM && kill -- -\$\$" SIGINT SIGTERM EXIT
/usr/bin/qemu-system-x86_64 \\
  -name devops-linux-x86_64 \\
  -machine type=q35,accel=kvm \\
  -device virtio-vga-gl,id=video.0,max_outputs=1,hostmem=64M \\
  -vga none \\
  -display gtk,gl=on,show-cursor=on,zoom-to-fit=off \\
  -cpu host \\
  -drive file=${local.build_name_qemu},if=virtio,cache=writeback,discard=unmap,detect-zeroes=unmap,format=qcow2 \\
  -drive file=/usr/share/OVMF/x64/OVMF_CODE.secboot.4m.fd,if=pflash,unit=0,format=raw,readonly=on \\
  -drive file=efivars.fd,if=pflash,unit=1,format=raw \\
  -smp ${var.cpu_cores},sockets=1,cores=${var.cpu_cores},maxcpus=${var.cpu_cores} -m ${var.memory}M \\
  -netdev user,id=user.0,hostfwd=tcp::9091-:9090 -device virtio-net,netdev=user.0 \\
  -audio driver=pa,model=hda,id=snd0 -device hda-output,audiodev=snd0 \\
  -device virtio-mouse -device virtio-keyboard \\
  -rtc base=utc,clock=host \\
  -virtfs local,path=../artifacts,mount_tag=artifacts.0,security_model=passthrough,id=artifacts.0

# /usr/bin/swtpm socket --tpm2 --tpmstate dir="..." --ctrl type=unixio,path=".../vtpm.sock"
# -device tpm-tis,tpmdev=tpm0 -tpmdev emulator,id=tpm0,chardev=vtpm -chardev "socket,id=vtpm,path=.../vtpm.sock"

# -netdev user,id=user.0,[...]
# -netdev socket,id=user.1,listen=:23568 -device virtio-net,netdev=user.1
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
  -device virtio-mouse -device virtio-keyboard \\
  -rtc base=utc,clock=host
EOF
chmod +x output/devops-linux/devops-linux-x86_64.pxe.sh
# remove -display gtk,gl=on for no 3d acceleration
# -display none, -daemonize, hostfwd=::12457-:22 for running as a daemonized server
EOS
    ]
    only_on = ["linux"]
  }
  
  provisioner "shell" {
    inline = [
      "/bin/sed -i '/^# cloud-init build/{x;:a;n;/#~cloud-init build/ba};d' /etc/ssh/sshd_config",
      "/bin/sed -i '/^provisioning/d' /etc/passwd",
      "/bin/sed -i '/^provisioning/d' /etc/shadow",
    ]
  }
}
