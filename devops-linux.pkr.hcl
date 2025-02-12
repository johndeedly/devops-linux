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


variable "sound_driver" {
  type = string
}

variable "accel_graphics" {
  type = string
}

variable "verbose" {
  type    = bool
  default = false
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
  default = false
}

variable "package_manager" {
  type    = string
  default = "pacman"
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
  vtpm                 = true
  tpm_device_type      = "tpm-tis"
  efi_boot             = true
  efi_firmware_code    = "/usr/share/OVMF/x64/OVMF_CODE.secboot.4m.fd"
  efi_firmware_vars    = "/usr/share/OVMF/x64/OVMF_VARS.4m.fd"
  sockets              = 1
  cores                = var.cpu_cores
  threads              = 1
  qemuargs             = [["-rtc", "base=utc,clock=host"], ["-device", "virtio-mouse"], ["-device", "virtio-keyboard"]]
  headless             = var.headless
  iso_checksum         = "none"
  iso_url              = "archlinux-x86_64-cidata.iso"
  output_directory     = "output/devops-linux"
  ssh_username         = "root"
  ssh_password         = "packer-build-passwd"
  ssh_timeout          = "10m"
  vm_name              = local.build_name_qemu
}


source "virtualbox-iso" "default" {
  shutdown_command         = "/sbin/poweroff"
  disk_size                = 524288
  memory                   = var.memory
  format                   = "ova"
  guest_additions_mode     = "disable"
  guest_os_type            = "ArchLinux_64"
  hard_drive_discard       = true
  hard_drive_interface     = "virtio"
  hard_drive_nonrotational = true
  headless                 = var.headless
  iso_checksum             = "none"
  iso_interface            = "virtio"
  iso_url                  = "archlinux-x86_64-cidata.iso"
  output_directory         = "output/devops-linux"
  output_filename          = "../devops-linux-x86_64"
  ssh_username             = "root"
  ssh_password             = "packer-build-passwd"
  ssh_timeout              = "10m"
  vboxmanage               = [["modifyvm", "{{ .Name }}", "--chipset", "ich9", "--firmware", "efi", "--cpus", "${var.cpu_cores}", "--audio-driver", "${var.sound_driver}", "--audio-out", "on", "--audio-enabled", "on", "--usb", "on", "--usb-xhci", "on", "--clipboard", "hosttoguest", "--draganddrop", "hosttoguest", "--graphicscontroller", "vmsvga", "--acpi", "on", "--ioapic", "on", "--apic", "on", "--accelerate3d", "${var.accel_graphics}", "--accelerate2dvideo", "on", "--vram", "128", "--pae", "on", "--nested-hw-virt", "on", "--paravirtprovider", "kvm", "--hpet", "on", "--hwvirtex", "on", "--largepages", "on", "--vtxvpid", "on", "--vtxux", "on", "--biosbootmenu", "messageandmenu", "--rtcuseutc", "on", "--nictype1", "virtio", "--macaddress1", "auto"], ["sharedfolder", "add", "{{ .Name }}", "--name", "host.0", "--hostpath", "output/"]]
  vboxmanage_post          = [["modifyvm", "{{ .Name }}", "--macaddress1", "auto"], ["sharedfolder", "remove", "{{ .Name }}", "--name", "host.0"]]
  vm_name                  = local.build_name_virtualbox
  skip_export              = true
  keep_registered          = true
}


build {
  sources = ["source.qemu.default", "source.virtualbox-iso.default"]

  provisioner "shell" {
    inline            = ["cloud-init status --wait"]
    valid_exit_codes  = [0, 2]
  }

  provisioner "file" {
    source      = "/cidata_log"
    destination = "output/devops-linux-cidata.log"
    direction   = "download"
  }

  provisioner "file" {
    source      = "/var/cache/pacman/pkg/"
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
    inline           = ["cloud-init status --wait"]
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
    inline           = ["cloud-init status --wait"]
    valid_exit_codes = [0, 2]
  }

  provisioner "file" {
    source      = "/cidata_log"
    destination = "output/devops-linux-cidata.log"
    direction   = "download"
  }

  provisioner "file" {
    source      = "/var/cache/${var.package_manager}/"
    destination = "database/stage"
    direction   = "download"
  }

  provisioner "shell" {
    inline = ["mkdir -p /srv/pxe /srv/docker"]
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

  provisioner "shell-local" {
    inline = [<<EOS
tee output/devops-linux/devops-linux-x86_64.run.sh <<EOF
#!/usr/bin/env bash
trap "trap - SIGTERM && kill -- -\$\$" SIGINT SIGTERM EXIT
mkdir -p "/tmp/swtpm.0"
/usr/bin/swtpm socket --tpm2 --tpmstate dir="/tmp/swtpm.0" --ctrl type=unixio,path="/tmp/swtpm.0/vtpm.sock" &
/usr/bin/qemu-system-x86_64 \\
  -name devops-linux-x86_64 \\
  -machine type=q35,accel=kvm \\
  -device virtio-vga,id=video.0,max_outputs=1 \\
  -vga none \\
  -display gtk,gl=on,show-cursor=on \\
  -cpu host \\
  -drive file=${local.build_name_qemu},if=virtio,cache=writeback,discard=unmap,detect-zeroes=unmap,format=qcow2 \\
  -device tpm-tis,tpmdev=tpm0 -tpmdev emulator,id=tpm0,chardev=vtpm -chardev socket,id=vtpm,path=/tmp/swtpm.0/vtpm.sock \\
  -drive file=/usr/share/OVMF/x64/OVMF_CODE.secboot.4m.fd,if=pflash,unit=0,format=raw,readonly=on \\
  -drive file=efivars.fd,if=pflash,unit=1,format=raw \\
  -smp ${var.cpu_cores},sockets=1,cores=${var.cpu_cores},maxcpus=${var.cpu_cores} -m ${var.memory}M \\
  -netdev user,id=user.0,hostfwd=tcp::9091-:9090 -device virtio-net,netdev=user.0 \\
  -audio driver=pa,model=hda,id=snd0 -device hda-output,audiodev=snd0 \\
  -device virtio-mouse -device virtio-keyboard \\
  -rtc base=utc,clock=host
EOF
# remove -display gtk,gl=on for no 3d acceleration
# -display none, -daemonize, hostfwd=::12345-:22 for running as a daemonized server
chmod +x output/devops-linux/devops-linux-x86_64.run.sh
EOS
    ]
    only_on = ["linux"]
  }
}
