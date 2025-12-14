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


variable "config_path" {
  type    = string
  default = "config/setup.yml"
}

locals {
  config                = yamldecode(file(var.config_path))
  package_manager       = local.config.distros[local.config.setup.distro]
  package_cache         = local.config.packer.create_package_cache
  build_name_qemu       = join(".", ["${local.config.setup.distro}-x86_64", replace(timestamp(), ":", "-"), "qcow2"])
  build_name_virtualbox = join(".", ["${local.config.setup.distro}-x86_64", replace(timestamp(), ":", "-")])
  open_ports_virtualbox = concat(["modifyvm", "{{ .Name }}", "--natpf1", "delete", "packercomm"], flatten(setproduct(["--natpf1"], [ for elem in local.config.packer.open_ports : format("%s-%d,%s,,%d,,%d", elem.protocol, elem.host, elem.protocol, elem.host, elem.vm) ])))
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
  swtpm_sbin            = "/sbin/swtpm"
  swtpm_bin             = "/bin/swtpm"
  has_swtpm_sbin        = fileexists(local.swtpm_sbin)
  has_swtpm_bin         = fileexists(local.swtpm_bin)
  can_swtpm             = local.has_swtpm_sbin ? true : local.has_swtpm_bin ? true : false
  can_swtpm_vbox        = local.has_swtpm_sbin ? "2.0" : local.has_swtpm_bin ? "2.0" : "none"
  qemu_intro            = <<EOF
#!/usr/bin/env bash
trap "trap - SIGTERM && kill -- -\$\$" SIGINT SIGTERM EXIT
QEMUPARAMS=(
  "-name" "devops-linux-x86_64"
  "-machine" "type=q35,accel=kvm"
)
if [ -d /sys/module/kvm_intel ] && grep -q "[1Y]" </sys/module/kvm_intel/parameters/nested; then
  QEMUPARAMS+=(
    "-cpu" "qemu64,+vmx,+aes,+popcnt,+pni,+sse4.1,+sse4.2,+ssse3,+avx,+avx2,+bmi1,+bmi2,+f16c,+fma,+abm,+movbe,+xsave"
  )
elif [ -d /sys/module/kvm_amd ] && grep -q "[1Y]" </sys/module/kvm_amd/parameters/nested; then
  QEMUPARAMS+=(
    "-cpu" "qemu64,+svm,+aes,+popcnt,+pni,+sse4.1,+sse4.2,+ssse3,+avx,+avx2,+bmi1,+bmi2,+f16c,+fma,+abm,+movbe,+xsave"
  )
else
  QEMUPARAMS+=(
    "-cpu" "qemu64,+aes,+popcnt,+pni,+sse4.1,+sse4.2,+ssse3,+avx,+avx2,+bmi1,+bmi2,+f16c,+fma,+abm,+movbe,+xsave"
  )
fi
EOF
  qemu_qcow2            = <<EOF
QEMUPARAMS+=(
  "-drive" "file=${local.build_name_qemu},if=virtio,cache=writeback,discard=unmap,detect-zeroes=unmap,format=qcow2"
%{ for index in range(1, length(local.config.packer.disk_sizes_mib)) ~}
  "-drive" "file=${local.build_name_qemu}-${index},if=virtio,cache=writeback,discard=unmap,detect-zeroes=unmap,format=qcow2"
%{ endfor ~}
)
EOF
  qemu_no_display       = <<EOF
QEMUPARAMS+=(
  "-device" "virtio-vga,id=video.0,max_outputs=1,hostmem=64M"
  "-vga" "none" "-display" "none"
)
EOF
  qemu_no_gl            = <<EOF
QEMUPARAMS+=(
  "-device" "virtio-vga,id=video.0,max_outputs=1,hostmem=64M"
  "-vga" "none" "-display" "gtk,gl=off,show-cursor=on,zoom-to-fit=off"
)
EOF
  qemu_gl               = <<EOF
QEMUPARAMS+=(
  "-device" "virtio-vga-gl,id=video.0,max_outputs=1,hostmem=64M"
  "-vga" "none" "-display" "gtk,gl=on,show-cursor=on,zoom-to-fit=off"
)
EOF
  qemu_efi              = <<EOF
if [ -f "${local.ovmf_code_arch}" ]; then
  QEMUPARAMS+=(
    "-drive" "file=${local.ovmf_code_arch},if=pflash,unit=0,format=raw,readonly=on"
    "-drive" "file=efivars.fd,if=pflash,unit=1,format=raw"
  )
elif [ -f "${local.ovmf_code_debian}" ]; then
  QEMUPARAMS+=(
    "-drive" "file=${local.ovmf_code_debian},if=pflash,unit=0,format=raw,readonly=on"
    "-drive" "file=efivars.fd,if=pflash,unit=1,format=raw"
  )
fi
EOF
  qemu_efi_pxe          = <<EOF
if [ -f "${local.ovmf_code_arch}" ]; then
  cp "${local.ovmf_vars_arch}" pxevars.fd
  QEMUPARAMS+=(
    "-drive" "file=${local.ovmf_code_arch},if=pflash,unit=0,format=raw,readonly=on"
    "-drive" "file=pxevars.fd,if=pflash,unit=1,format=raw"
  )
elif [ -f "${local.ovmf_code_debian}" ]; then
  cp "${local.ovmf_vars_debian}" pxevars.fd
  QEMUPARAMS+=(
    "-drive" "file=${local.ovmf_code_debian},if=pflash,unit=0,format=raw,readonly=on"
    "-drive" "file=pxevars.fd,if=pflash,unit=1,format=raw"
  )
fi
EOF
  qemu_swtpm            = <<EOF
if command -v swtpm 2>&1 >/dev/null; then
  if ! [ -e vtpm.0/vtpm.sock ]; then
    mkdir -p vtpm.0
    swtpm socket --tpm2 --tpmstate dir="vtpm.0" --ctrl type=unixio,path="vtpm.0/vtpm.sock" &
  fi
  QEMUPARAMS+=(
    "-device" "tpm-tis,tpmdev=tpm.0" "-tpmdev" "emulator,id=tpm.0,chardev=vtpm"
    "-chardev" "socket,id=vtpm,path=vtpm.0/vtpm.sock"
  )
fi
EOF
  qemu_net_user         = <<EOF
QEMUPARAMS+=(
  "-netdev" "user,id=user.0%{ for elem in local.config.packer.open_ports ~},hostfwd=${elem.protocol}::${elem.host}-:${elem.vm}%{ endfor ~}" "-device" "virtio-net,netdev=user.0"
)
EOF
  qemu_net_router       = <<EOF
QEMUPARAMS+=(
  "-netdev" "user,id=user.0%{ for elem in local.config.packer.open_ports ~},hostfwd=${elem.protocol}::${elem.host}-:${elem.vm}%{ endfor ~}" "-device" "virtio-net,netdev=user.0"
  "-netdev" "socket,id=user.1,listen=:${local.config.packer.router_socket_listen_port}" "-device" "virtio-net,netdev=user.1"
)
EOF
  qemu_net_pxe          = <<EOF
# you need(!!) a rng device to enable uefi pxe boot on nics, as ovmf out of security concerns disables netboot without it
# https://blog.ledoian.cz/qemu-ovmf-netboot.html
# https://forum.proxmox.com/threads/proxmox-ve-8-4-0-unable-to-pxe-boot-under-ovmf.168220/
# https://pve.proxmox.com/wiki/Roadmap#8.4-known-issues
QEMUPARAMS+=(
  "-netdev" "socket,id=user.0,connect=:${local.config.packer.router_socket_listen_port}" "-device" "virtio-net,netdev=user.0,bootindex=1"
  "-device" "virtio-rng"
)
EOF
  qemu_outro            = <<EOF
QEMUPARAMS+=(
  "-smp" "${local.config.packer.cpu_cores},sockets=1,cores=${local.config.packer.cpu_cores},maxcpus=${local.config.packer.cpu_cores}" "-m" "${local.config.packer.memory_mib}M"
  "-audio" "driver=pa,model=hda,id=snd0" "-device" "hda-output,audiodev=snd0"
  "-device" "virtio-tablet" "-device" "virtio-keyboard"
  "-rtc" "base=utc,clock=host"
)
if [ -d "../artifacts" ]; then
  QEMUPARAMS+=(
    "-virtfs" "local,path=../artifacts,mount_tag=artifacts.0,security_model=passthrough,id=artifacts.0"
  )
fi
EOF
  qemu_outro_server     = <<EOF
QEMUPARAMS+=(
  "-smp" "${local.config.packer.cpu_cores},sockets=1,cores=${local.config.packer.cpu_cores},maxcpus=${local.config.packer.cpu_cores}" "-m" "${local.config.packer.memory_mib}M"
  "-device" "virtio-tablet" "-device" "virtio-keyboard"
  "-rtc" "base=utc,clock=host"
  "-daemonize"
)
if [ -d "../artifacts" ]; then
  QEMUPARAMS+=(
    "-virtfs" "local,path=../artifacts,mount_tag=artifacts.0,security_model=passthrough,id=artifacts.0"
  )
fi
EOF
  qemu_exec             = <<EOF
/usr/bin/qemu-system-x86_64 "\$${QEMUPARAMS[@]}"
EOF
}


source "qemu" "default" {
  boot_wait            = "3s"
  boot_command         = ["<enter>"]
  disk_size            = format("%sM", local.config.packer.disk_sizes_mib[0])
  disk_additional_size = formatlist("%sM", slice(local.config.packer.disk_sizes_mib, 1, length(local.config.packer.disk_sizes_mib)))
  memory               = local.config.packer.memory_mib
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
  vtpm                 = local.can_swtpm
  sockets              = 1
  cores                = local.config.packer.cpu_cores
  threads              = 1
  qemuargs             = [
    ["-virtfs", "local,path=./database,mount_tag=database.0,security_model=mapped,id=database.0"],
    ["-rtc", "base=utc,clock=host"],
    ["-device", "virtio-tablet"],
    ["-device", "virtio-keyboard"]
  ]
  headless             = local.config.packer.headless
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
  disk_size                = local.config.packer.disk_sizes_mib[0]
  disk_additional_size     = slice(local.config.packer.disk_sizes_mib, 1, length(local.config.packer.disk_sizes_mib))
  memory                   = local.config.packer.memory_mib
  format                   = "ova"
  guest_additions_mode     = "disable"
  guest_os_type            = "Linux_64"
  hard_drive_discard       = true
  hard_drive_interface     = "virtio"
  hard_drive_nonrotational = true
  chipset                  = "ich9"
  firmware                 = "efi"
  cpus                     = local.config.packer.cpu_cores
  usb                      = true
  nic_type                 = "virtio"
  gfx_controller           = "vboxsvga"
  gfx_accelerate_3d        = true
  gfx_vram_size            = 64
  headless                 = local.config.packer.headless
  iso_checksum             = "none"
  iso_interface            = "virtio"
  iso_url                  = "devops-x86_64-cidata.iso"
  output_directory         = "output/devops-linux"
  output_filename          = "devops-linux-x86_64"
  ssh_username             = "root"
  ssh_keypair_name         = "ssh_packer_key"
  ssh_private_key_file     = "./ssh_packer_key"
  ssh_timeout              = "10m"
  vboxmanage               = [["modifyvm", "{{ .Name }}", "--tpm-type", "${local.can_swtpm_vbox}", "--audio-out", "on", "--audio-enabled", "on", "--usb-xhci", "on", "--clipboard", "hosttoguest", "--draganddrop", "hosttoguest", "--acpi", "on", "--ioapic", "on", "--apic", "on", "--pae", "on", "--nested-hw-virt", "on", "--paravirtprovider", "kvm", "--hpet", "on", "--hwvirtex", "on", "--largepages", "on", "--vtxvpid", "on", "--vtxux", "on", "--biosbootmenu", "messageandmenu", "--rtcuseutc", "on", "--macaddress1", "auto"], ["sharedfolder", "add", "{{ .Name }}", "--name", "database.0", "--hostpath", "./database"]]
  vboxmanage_post          = [local.open_ports_virtualbox, ["modifyvm", "{{ .Name }}", "--macaddress1", "auto"], ["sharedfolder", "remove", "{{ .Name }}", "--name", "database.0"]]
  vm_name                  = local.build_name_virtualbox
  skip_export              = true
  keep_registered          = true
}


build {
  sources = ["source.qemu.default", "source.virtualbox-iso.default"]

  provisioner "shell" {
    inline = ["touch /cidata_stage0_log"]
  }

  provisioner "file" {
    source      = "/cidata_stage0_log"
    destination = "output/devops-linux-cidata-stage0.log"
    direction   = "download"
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

  provisioner "shell" {
    expect_disconnect = true
    script            = "config/99_packer_reboot.sh"
    skip_clean        = true
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
    source      = local.package_cache ? "/var/cache/${local.package_manager}/" : ""
    destination = "database/stage"
    direction   = "download"
  }

  provisioner "file" {
    source      = local.package_cache ? "/usr/share/keyrings/" : ""
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
${local.qemu_intro}
${local.qemu_qcow2}
${local.qemu_no_gl}
${local.qemu_efi}
${local.qemu_swtpm}
${local.qemu_net_user}
${local.qemu_outro}
${local.qemu_exec}
EOF
chmod +x output/devops-linux/devops-linux-x86_64.run.sh
tee output/devops-linux/devops-linux-x86_64.gl.sh <<EOF
${local.qemu_intro}
${local.qemu_qcow2}
${local.qemu_gl}
${local.qemu_efi}
${local.qemu_swtpm}
${local.qemu_net_user}
${local.qemu_outro}
${local.qemu_exec}
EOF
chmod +x output/devops-linux/devops-linux-x86_64.gl.sh
tee output/devops-linux/devops-linux-x86_64.pxe.bios.sh <<EOF
${local.qemu_intro}
${local.qemu_no_gl}
${local.qemu_net_pxe}
${local.qemu_outro}
${local.qemu_exec}
EOF
chmod +x output/devops-linux/devops-linux-x86_64.pxe.bios.sh
tee output/devops-linux/devops-linux-x86_64.pxe.uefi.sh <<EOF
${local.qemu_intro}
${local.qemu_no_gl}
${local.qemu_efi_pxe}
${local.qemu_net_pxe}
${local.qemu_outro}
${local.qemu_exec}
EOF
chmod +x output/devops-linux/devops-linux-x86_64.pxe.uefi.sh
tee output/devops-linux/devops-linux-x86_64.netdev.sh <<EOF
${local.qemu_intro}
${local.qemu_qcow2}
${local.qemu_no_gl}
${local.qemu_efi}
${local.qemu_swtpm}
${local.qemu_net_router}
${local.qemu_outro}
${local.qemu_exec}
EOF
chmod +x output/devops-linux/devops-linux-x86_64.netdev.sh
tee output/devops-linux/devops-linux-x86_64.srv.sh <<EOF
${local.qemu_intro}
${local.qemu_qcow2}
${local.qemu_no_display}
${local.qemu_net_user}
${local.qemu_outro_server}
${local.qemu_exec}
EOF
chmod +x output/devops-linux/devops-linux-x86_64.srv.sh
EOS
    ]
    only_on = ["linux"]
  }
  
  provisioner "shell" {
    script            = "config/98_packer_lockdown.sh"
  }
}
