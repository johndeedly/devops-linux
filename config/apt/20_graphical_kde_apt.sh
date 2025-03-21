#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install \
  pipewire pipewire-pulse pipewire-jack pipewire-alsa wireplumber pamixer pavucontrol playerctl alsa-utils qpwgraph rtkit \
  xorg xinit x11-xserver-utils xclip xsel brightnessctl arandr dunst libnotify4 engrampa \
  libinput10 xserver-xorg-input-libinput xinput kitty dex xrdp lightdm lightdm-gtk-greeter \
  elementary-icon-theme fonts-dejavu fonts-liberation fonts-font-awesome fonts-hanazono \
  fonts-baekmuk fonts-noto-color-emoji \
  cups ipp-usb libreoffice libreoffice-l10n-de krita freerdp3-x11 freerdp3-wayland gitg keepassxc pdf-presenter-console \
  bluez blueman \
  texlive-binaries xdg-desktop-portal xdg-desktop-portal-kde wine wine64 winetricks mpv gpicview \
  flatpak chromium virt-manager \
  ghostscript gsfonts foomatic-db-engine foomatic-db printer-driver-gutenprint hplip \
  kde-standard libpam-kwallet5 system-config-printer

if grep -q Debian /proc/version; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install firefox-esr
elif grep -q Ubuntu /proc/version; then
  add-apt-repository ppa:mozillateam/ppa
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y update
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install firefox-esr
fi

# configure network manager
mkdir -p /etc/NetworkManager/conf.d
tee /etc/NetworkManager/conf.d/10-virtio-net-managed-devices.conf <<EOF
[devices-virtio-net-managed]
match-device=driver:virtio_net
managed=true
EOF
tee /etc/NetworkManager/NetworkManager.conf <<'EOF'
[main]
plugins=ifupdown,keyfile
dns=systemd-resolved

[keyfile]
unmanaged-devices=*,except:type:ethernet,except:type:wifi,except:type:wwan

[ifupdown]
managed=true

[device]
wifi.scan-rand-mac-address=yes
EOF
systemctl unmask NetworkManager || true
systemctl enable NetworkManager

# add all users to group libvirt
getent passwd | while IFS=: read -r username x uid gid gecos home shell; do
  if [ -n "$home" ] && [ -d "$home" ] && [ "$home" != "/" ]; then
    if [ "$uid" -eq 0 ] || [ "$uid" -ge 1000 ]; then
      echo ":: add $username to group libvirt"
      usermod -a -G libvirt $username
    fi
  fi
done

# add flathub repo to system when not present
flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# install obsidian as flatpak
flatpak install --system flathub md.obsidian.Obsidian

# enable lightdm
rm /etc/systemd/system/display-manager.service || true
ln -s /usr/lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service

# create profile for X11 sessions
tee /etc/skel/.xprofile <<EOF
#!/bin/sh
[ -f ~/.bash_profile ] && . ~/.bash_profile
EOF

# menu key is equal to super key
tee /etc/skel/.Xmodmap <<EOF
keysym Menu = Super_R
EOF

# configure firefox
mkdir -p /usr/lib/firefox/distribution
(
  jq -Rs '{"policies":{"Extensions":{"Install":split("\n")|map(if index(" ") then split(" ")|"https://addons.mozilla.org/firefox/downloads/latest/"+.[0]+"/" else empty end),"Locked":split("\n")|map(if index(" ") then split(" ")|.[1] else empty end)}}}' <<'EOF'
adguard-adblocker adguardadblocker@adguard.com
keepassxc-browser keepassxc-browser@keepassxc.org
single-file {531906d3-e22f-4a6c-a102-8057b88a1a63}
sponsorblock sponsorBlocker@ajay.app
forget_me_not forget-me-not@lusito.info
return-youtube-dislikes {762f9885-5a13-4abd-9c77-433dcd38b8fd}
adblock-for-youtube-tm {0ac04bdb-d698-452f-8048-bcef1a3f4b0d}
EOF
) | tee /usr/lib/firefox/distribution/policies.json

# configure chromium
mkdir -p /etc/chromium/policies/managed
tee /etc/chromium/policies/managed/adblock.json <<'EOF'
{
    "BlockThirdPartyCookies": true,
    "AdsSettingForIntrusiveAdsSites": 2,
    "DNSInterceptionChecksEnabled": false,
    "ExtensionManifestV2Availability": 2,
    "DnsOverHttpsMode": "off"
}
EOF
tee /etc/chromium/policies/managed/default-settings.json <<'EOF'
{
    "ShowHomeButton": true,
    "ChromeAppsEnabled": false,
    "DefaultBrowserSettingEnabled": false,
    "HardwareAccelerationModeEnabled": true
}
EOF
(
jq -Rs '{"ExtensionInstallForcelist":split("\n")|map(if match(".") then .+";https://clients2.google.com/service/update2/crx" else empty end)}' <<'EOF'
bgnkhhnnamicmpeenaelnjfhikgbkllg
mpiodijhokgodhhofbcjdecpffjipkle
mnjggcdmjocbbbhaepdhchncahnbgone
cmedhionkhpnakcndndgjdbohmhepckk
oboonakemofpalcgghocfoadofidjkkk
hdadmgabliibighlbejhlglfjgplfmhb
gebbhagfogifgggkldgodflihgfeippi
cnkdjjdmfiffagllbiiilooaoofcoeff
EOF
) | tee /etc/chromium/policies/managed/extensions-default.json
tee /etc/chromium/policies/managed/telemetry-off.json <<'EOF'
{
    "MetricsReportingEnabled": false,
    "SafeBrowsingProtectionLevel": 0,
    "AbusiveExperienceInterventionEnforce": false,
    "GoogleSearchSidePanelEnabled": false,
    "AdvancedProtectionAllowed": false,
    "BrowserSignin": 0
}
EOF
tee /etc/chromium/policies/managed/duckduckgo.json <<'EOF'
{
    "DefaultSearchProviderEnabled": true,
    "DefaultSearchProviderName": "DuckDuckGo",
    "DefaultSearchProviderSearchURL": "https://duckduckgo.com/?q={searchTerms}",
    "DefaultSearchProviderSuggestURL": "https://duckduckgo.com/ac/?type=list&kl=de-de&q={searchTerms}"
}
EOF
tee /etc/chromium/policies/managed/restore-session.json <<'EOF'
{
    "RestoreOnStartup": 1
}
EOF

#
# configure kde desktop
#

# set application mimetype defaults
FILELIST=(
  /usr/share/applications/libreoffice-math.desktop
  /usr/share/applications/libreoffice-draw.desktop
  /usr/share/applications/libreoffice-calc.desktop
  /usr/share/applications/libreoffice-writer.desktop
  /usr/share/applications/libreoffice-impress.desktop
  /usr/share/applications/kitty.desktop
  /usr/share/applications/chromium.desktop
  /usr/share/applications/engrampa.desktop
  /usr/share/applications/mpv.desktop
  /usr/share/applications/org.kde.kate.desktop
  /usr/share/applications/org.kde.dolphin.desktop
)
tee /tmp/mimeapps.list.added <<EOF
[Added Associations]
EOF
tee /tmp/mimeapps.list.default <<EOF
[Default Applications]
EOF
for file in "${FILELIST[@]}"; do
  if [ -f "$file" ]; then
    grep 'MimeType=' "$file" | sed -e 's/.*=//' -e 's/;/\n/g' | while read -r line; do
      if [ -n "$line" ]; then
        # add to existing entry
        if grep -q "$line" /tmp/mimeapps.list.added; then
          sed -i 's|\('"$line"'=.*\)|\1;'"${file##*/}"'|' /tmp/mimeapps.list.added
        else
          tee -a /tmp/mimeapps.list.added <<EOF
${line}=${file##*/}
EOF
        fi
        # overwrite existing entry -> last come, first served
        if grep -q "$line" /tmp/mimeapps.list.default; then
          sed -i 's|'"$line"'=.*|'"$line"'='"${file##*/}"'|' /tmp/mimeapps.list.default
        else
          tee -a /tmp/mimeapps.list.default <<EOF
${line}=${file##*/}
EOF
        fi
      fi
    done
  fi
done
cat /tmp/mimeapps.list.added /tmp/mimeapps.list.default > /etc/xdg/mimeapps.list
rm /tmp/mimeapps.list.added /tmp/mimeapps.list.default

# software cursor when running inside a vm
tee /usr/local/bin/vm-check.sh <<'EOF'
#!/usr/bin/env bash

if systemd-detect-virt -q; then
  if ! [ -d /etc/X11/xorg.conf.d ]; then
    mkdir -p /etc/X11/xorg.conf.d
  fi
  tee /etc/X11/xorg.conf.d/05-swcursor.conf <<EOX
Section "Device"
  Identifier "graphicsdriver"
  Option     "SWcursor" "on"
EndSection
EOX
  systemctl --user set-environment KWIN_FORCE_SW_CURSOR=1 WLR_NO_HARDWARE_CURSORS=1 MUTTER_DEBUG_DISABLE_HW_CURSORS=1
  dbus-update-activation-environment --systemd --all KWIN_FORCE_SW_CURSOR=1 WLR_NO_HARDWARE_CURSORS=1 MUTTER_DEBUG_DISABLE_HW_CURSORS=1
else
  if [ -f /etc/X11/xorg.conf.d/05-swcursor.conf ]; then
    rm /etc/X11/xorg.conf.d/05-swcursor.conf
  fi
fi
EOF
chmod +x /usr/local/bin/vm-check.sh
tee /etc/systemd/system/vm-check.service <<EOF
[Unit]
Description=Check for virtual environment and enable software cursor

[Service]
Type=simple
StandardInput=null
StandardOutput=journal
StandardError=journal
ExecStart=/usr/local/bin/vm-check.sh

[Install]
WantedBy=sysinit.target
EOF
systemctl enable vm-check

# global xterm fallback to kitty terminal
ln -s /usr/bin/kitty /usr/local/bin/xterm

# configure global shortcuts
mkdir -p /etc/skel/.config
tee -a /etc/skel/.config/kglobalshortcutsrc <<'EOF'
[services][kitty.desktop]
_launch=Ctrl+Alt+T
EOF

# apply skeleton to all users
getent passwd | while IFS=: read -r username x uid gid gecos home shell; do
  if [ -n "$home" ] && [ -d "$home" ] && [ "$home" != "/" ]; then
    if [ "$uid" -eq 0 ] || [ "$uid" -ge 1000 ]; then
      echo ":: apply skeleton to $home [$username $uid:$gid]"
      rsync -a --chown=$uid:$gid /etc/skel/ "$home"
    fi
  fi
done

# sync everything to disk
sync

# cleanup
rm -- "${0}"
