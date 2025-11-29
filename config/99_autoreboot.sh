#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# double fork trick to prevent the subprocess from exiting
echo "[ ## ] Wait for cloud-init to finish"
( (
  # valid exit codes are 0 or 2
  cloud-init status --long --format yaml --wait | sed -e 's/^/>>> /g'
  ret=$?
  if [ $ret -eq 0 ] || [ $ret -eq 2 ]; then
    echo "[ OK ] Rebooting the system"
    VMLINUZ=$(find /boot -maxdepth 1 -name 'vmlinuz*' | sort -Vru | head -n1)
    INITRD=$(find /boot -maxdepth 1 \( \( -name 'initramfs*' -a ! -name '*fallback*' -a ! -name '*pxe*' \) -o -name 'initrd*' \) | sort -Vru | head -n1)
    GRUB_CMDLINE="console=ttyS0,115200 console=tty1 acpi=force acpi_osi=Linux loglevel=3"
    GRUB_ROOT=( $(lsblk -no PARTLABEL,UUID,FSTYPE | sed -e '/^root/I!d' | head -n 1 | awk '{ print $2" "$3 }') )
    if [ "x${GRUB_ROOT[1]}" == "xbtrfs" ]; then
      echo "[ OK ] Detected btrfs root, enable zstd compression"
      GRUB_CMDLINE="$GRUB_CMDLINE rootflags=compress-force=zstd:4"
    fi
    if command -v kexec 2>&1 >/dev/null && [ -n "${GRUB_ROOT[0]}" ] && [ -n "$VMLINUZ" ] && [ -e "$VMLINUZ" ] && [ -n "$INITRD" ] && [ -e "$INITRD" ]; then
      echo "[ OK ] Found next kernel '$VMLINUZ' and initramfs '$INITRD'"
      echo "[ OK ] Booting into root '${GRUB_ROOT[0]}'"
      kexec -l "$VMLINUZ" --initrd="$INITRD" --append="root=UUID=${GRUB_ROOT[0]} rw $GRUB_CMDLINE"
      for gpumod in amdgpu radeon nouveau i915 virtio-gpu vmwgfx; do
        modprobe -r "$gpumod" || true
      done
      echo "[ OK ] kexec now"
      systemctl kexec
    else
      echo "[ OK ] default reboot now"
      reboot now
    fi
  else
    echo "[FAIL] Unrecoverable error in provision steps"
  fi
) & )

# cleanup
[ -f "${0}" ] && rm -- "${0}"
