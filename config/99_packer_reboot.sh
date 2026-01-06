#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log; done)

# valid exit codes are 0 or 2
cloud-init status --long --format yaml --wait | sed -e 's/^/>>> /g'
ret=$?
if [ $ret -eq 0 ] || [ $ret -eq 2 ]; then
  echo "[ OK ] Rebooting the system"
  VMLINUZ=$(find /boot -maxdepth 1 -name 'vmlinuz*' | sort -Vru | head -n1)
  INITRD=$(find /boot -maxdepth 1 \( \( -name 'initramfs*' -a ! -name '*fallback*' -a ! -name '*pxe*' \) -o -name 'initrd*' \) | sort -Vru | head -n1)
  GRUB_CMDLINE="console=ttyS0,115200 console=tty1 acpi=force acpi_osi=Linux loglevel=3"
  GRUB_ROOT=( $(lsblk -no PARTTYPE,UUID,FSTYPE | sed -e '/^4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709/I!d' | awk 'NR==1{ print $2" "$3 }') )
  if [ "x${GRUB_ROOT[1]}" == "xbtrfs" ]; then
    echo "[ OK ] Detected btrfs root, enable zstd compression"
    GRUB_CMDLINE="$GRUB_CMDLINE rootflags=compress-force=zstd:4,noatime"
  fi
  if command -v kexec 2>&1 >/dev/null && [ -n "${GRUB_ROOT[0]}" ] && [ -n "$VMLINUZ" ] && [ -e "$VMLINUZ" ] && [ -n "$INITRD" ] && [ -e "$INITRD" ]; then
    echo "[ OK ] Found next kernel '$VMLINUZ' and initramfs '$INITRD'"
    echo "[ OK ] Booting into root '${GRUB_ROOT[0]}'"
    kexec -l "$VMLINUZ" --initrd="$INITRD" --append="root=UUID=${GRUB_ROOT[0]} rw $GRUB_CMDLINE"
    for gpumod in amdgpu radeon nouveau i915 virtio-gpu vmwgfx; do
      modprobe -r "$gpumod" || true
    done
    echo "[ -> ] kexec now"
    # double fork trick to prevent the subprocess from exiting
    ( ( sleep 2; systemctl kexec ) & )
    echo "[ OK ] wait for kexec"
  else
    echo "[ -> ] default reboot now"
    # double fork trick to prevent the subprocess from exiting
    ( ( sleep 2; reboot now ) & )
    echo "[ OK ] wait for reboot"
  fi
else
  echo "[FAIL] Unrecoverable error in provision steps"
fi
