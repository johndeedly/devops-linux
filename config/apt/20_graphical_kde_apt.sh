#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

if grep -q Ubuntu /proc/version; then
  until getent hosts archive.ubuntu.com >/dev/null 2>&1; do sleep 2; done
fi
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y update
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install \
  pipewire pipewire-pulse pipewire-jack pipewire-alsa wireplumber pamixer pavucontrol playerctl alsa-utils qpwgraph rtkit \
  xorg xinit x11-xserver-utils xclip xsel wl-clipboard brightnessctl arandr dunst libnotify4 engrampa \
  libinput10 xserver-xorg-input-libinput xinput dex lightdm slick-greeter \
  elementary-icon-theme fonts-dejavu fonts-liberation fonts-font-awesome fonts-hanazono \
  fonts-baekmuk fonts-noto-color-emoji \
  cups ipp-usb libreoffice libreoffice-l10n-de krita krdc gitg keepassxc pdf-presenter-console \
  bluez blueman \
  xdg-desktop-portal xdg-desktop-portal-kde wine wine64 winetricks mpv gpicview \
  flatpak virt-manager qpdf \
  texlive-latex-base texlive-latex-extra texlive-plain-generic \
  ghostscript gsfonts foomatic-db-engine foomatic-db printer-driver-gutenprint hplip \
  kde-standard libpam-kwallet5 system-config-printer konsole

# Ubuntu wayland session fix
if grep -q Ubuntu /proc/version; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install plasma-workspace-wayland
fi

# remove kde bloat
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y remove plasma-welcome

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
find /sys/class/net \( -name "en*" -o -name "eth*" \) -exec basename {} \; | while read -r line; do
  tee "/etc/NetworkManager/system-connections/$line.nmconnection" <<EOF
[connection]
id=$line
uuid=$(uuidgen)
type=ethernet
autoconnect=true
interface-name=$line

[ipv4]
method=auto

[ipv6]
addr-gen-mode=stable-privacy
method=auto
EOF
  chmod 600 "/etc/NetworkManager/system-connections/$line.nmconnection"
done
find /sys/class/net -name "wl*" -exec basename {} \; | while read -r line; do
  tee "/etc/NetworkManager/system-connections/$line.nmconnection" <<EOF
[connection]
id=$line
uuid=$(uuidgen)
type=wifi
autoconnect=true
interface-name=$line

[ipv4]
method=auto

[ipv6]
addr-gen-mode=stable-privacy
method=auto
EOF
  chmod 600 "/etc/NetworkManager/system-connections/$line.nmconnection"
done

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

# install zen browser as flatpak
flatpak install -y --noninteractive --system flathub app.zen_browser.zen

# install firefox as flatpak
flatpak install -y --noninteractive --system flathub org.mozilla.firefox

# install chromium as flatpak
flatpak install -y --noninteractive --system flathub org.chromium.Chromium

# install tor browser as flatpak
flatpak install -y --noninteractive --system flathub org.torproject.torbrowser-launcher

# configure zen (small hack starting zen in headless mode, immediately closing it afterwards
# as it cannot take a snapshot at this point)
( HOME=/etc/skel /bin/bash -c '
/usr/bin/flatpak run --branch=stable --arch=x86_64 --file-forwarding app.zen_browser.zen -screenshot
find /etc/skel/.var/app/app.zen_browser.zen -type f -name "prefs.js" | while read -r line; do
  profiledir="${line%"/prefs.js"}"
  echo "[ ## ] modify user config \"$line\""
  tee -a "$line" <<EOX
user_pref("zen.welcome-screen.seen", true);
user_pref("startup.homepage_welcome_url", "about:restartrequired");
user_pref("startup.homepage_welcome_url.additional", "about:newtab");
user_pref("extensions.autoDisableScopes", 14);
EOX
  mkdir -p "${profiledir}/extensions"
  while read -r name id; do
    wget -c -O "${profiledir}/extensions/${id}.xpi" --progress=dot:giga "https://addons.mozilla.org/firefox/downloads/latest/${name}/"
  done <<EOX
adguard-adblocker adguardadblocker@adguard.com
ghostery firefox@ghostery.com
single-file {531906d3-e22f-4a6c-a102-8057b88a1a63}
EOX
done
' ) &
pid=$!
wait $pid

# configure tor browser
#   extensions can be installed, but not configured to run in private mode out of the box
browserdir="/etc/skel/.var/app/org.torproject.torbrowser-launcher/data/torbrowser/tbb/x86_64/tor-browser/Browser"
mkdir -p "${browserdir}/distribution/extensions" "${browserdir}/TorBrowser/Data/Browser/profile.default/"
while read -r name id; do
  wget -c -O "${browserdir}/extensions/${id}.xpi" --progress=dot:giga "https://addons.mozilla.org/firefox/downloads/latest/${name}/"
done <<EOX
adguard-adblocker adguardadblocker@adguard.com
ghostery firefox@ghostery.com
single-file {531906d3-e22f-4a6c-a102-8057b88a1a63}
EOX

# set slick greeter as default
tee -a /etc/lightdm/lightdm.conf <<EOF
[Seat:*]
greeter-show-manual-login=true
greeter-hide-users=true
greeter-session=slick-greeter
user-session=plasmawayland
guest-session=plasmawayland
autologin-session=plasmawayland
EOF

# configuration for slick-greeter
tee /etc/lightdm/slick-greeter.conf <<EOF
[Greeter]
# LightDM GTK+ Configuration
#
background=/usr/share/wallpapers/Next/contents/images/5120x2880.png
show-hostname=true
clock-format=%H:%M
EOF

# enable lightdm
rm /etc/systemd/system/display-manager.service || true
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure --frontend=noninteractive lightdm

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
mkdir -p /var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/x86_64/stable/policies
(
  jq -Rs '{"policies":{"Extensions":{"Install":split("\n")|map(if index(" ") then split(" ")|"https://addons.mozilla.org/firefox/downloads/latest/"+.[0]+"/" else empty end),"Locked":split("\n")|map(if index(" ") then split(" ")|.[1] else empty end)}}}' <<'EOF'
adguard-adblocker adguardadblocker@adguard.com
ghostery firefox@ghostery.com
single-file {531906d3-e22f-4a6c-a102-8057b88a1a63}
EOF
) | tee /var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/x86_64/stable/policies/policies.json

# configure chromium
mkdir -p /var/lib/flatpak/extension/org.chromium.Chromium.Extension.system-policies/x86_64/1/policies/managed
tee /var/lib/flatpak/extension/org.chromium.Chromium.Extension.system-policies/x86_64/1/policies/managed/adblock.json <<'EOF'
{
    "BlockThirdPartyCookies": true,
    "AdsSettingForIntrusiveAdsSites": 2,
    "DNSInterceptionChecksEnabled": false,
    "ExtensionManifestV2Availability": 2,
    "DnsOverHttpsMode": "off"
}
EOF
tee /var/lib/flatpak/extension/org.chromium.Chromium.Extension.system-policies/x86_64/1/policies/managed/default-settings.json <<'EOF'
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
mlomiejdfkolichcflejclcbmpeaniij
mpiodijhokgodhhofbcjdecpffjipkle
EOF
) | tee /var/lib/flatpak/extension/org.chromium.Chromium.Extension.system-policies/x86_64/1/policies/managed/extensions-default.json
tee /var/lib/flatpak/extension/org.chromium.Chromium.Extension.system-policies/x86_64/1/policies/managed/telemetry-off.json <<'EOF'
{
    "MetricsReportingEnabled": false,
    "SafeBrowsingProtectionLevel": 0,
    "AbusiveExperienceInterventionEnforce": false,
    "GoogleSearchSidePanelEnabled": false,
    "AdvancedProtectionAllowed": false,
    "BrowserSignin": 0
}
EOF
tee /var/lib/flatpak/extension/org.chromium.Chromium.Extension.system-policies/x86_64/1/policies/managed/searchprovider.json <<'EOF'
{
    "DefaultSearchProviderEnabled": true,
    "DefaultSearchProviderName": "Google",
    "DefaultSearchProviderSearchURL": "https://google.com/search?sourceid=chrome&q={searchTerms}",
    "DefaultSearchProviderSuggestURL": "https://google.com/complete/search?output=chrome&q={searchTerms}"
}
EOF
tee /var/lib/flatpak/extension/org.chromium.Chromium.Extension.system-policies/x86_64/1/policies/managed/restore-session.json <<'EOF'
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
  /usr/share/applications/org.kde.konsole.desktop
  /var/lib/flatpak/app/app.zen_browser.zen/current/active/export/share/applications/app.zen_browser.zen.desktop
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

# global xterm fallback to konsole terminal
ln -s /usr/bin/konsole /usr/local/bin/xterm

# configure global shortcuts
mkdir -p /etc/skel/.config
tee -a /etc/skel/.config/kglobalshortcutsrc <<'EOF'
[services][org.kde.konsole.desktop]
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

# enable rdp mDNS advertising
tee /etc/systemd/dnssd/rdp.dnssd <<EOF
[Service]
Name=%H
Type=_rdp._tcp
Port=3389
EOF

# open firewall for rdp access
ufw disable
ufw allow log 3389/tcp comment 'allow rdp'
ufw enable
ufw status verbose

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
