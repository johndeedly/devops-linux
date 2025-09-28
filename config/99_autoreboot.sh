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
    INITRD=$(find /boot -maxdepth 1 \( -name 'initramfs*' -o -name 'initrd*' \) | sort -Vru | head -n1)
    if [ -n "$VMLINUZ" ] && [ -e "$VMLINUZ" ] && [ -n "$INITRD" ] & [ -e "$INITRD" ]; then
      echo "[ OK ] Found next kernel '$VMLINUZ' and initramfs '$INITRD'"
      kexec -l "$VMLINUZ" --initrd="$INITRD" --reuse-cmdline
      for gpumod in amdgpu radeon nouveau i915 virtio-gpu vmwgfx; do
        modprobe -r "$gpumod" || true
      done
      echo "[ OK ] kexec now"
      systemctl kexec
    else
      reboot now
    fi
  else
    echo "[ FAILED ] Unrecoverable error in provision steps"
  fi
) & )

# cleanup
[ -f "${0}" ] && rm -- "${0}"
