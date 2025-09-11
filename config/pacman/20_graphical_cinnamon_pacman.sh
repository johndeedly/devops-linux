#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed \
  pipewire pipewire-pulse pipewire-jack pipewire-alsa wireplumber pamixer pavucontrol playerctl alsa-utils qpwgraph rtkit realtime-privileges \
  xorg-server xorg-xinit xorg-xrandr xclip xsel brightnessctl gammastep arandr dunst libnotify engrampa \
  flameshot libinput xf86-input-libinput xorg-xinput kitty wofi dex xrdp ibus ibus-typing-booster lightdm lightdm-slick-greeter \
  archlinux-wallpaper elementary-wallpapers elementary-icon-theme ttf-dejavu ttf-dejavu-nerd ttf-liberation ttf-font-awesome ttf-hanazono \
  ttf-hannom ttf-baekmuk noto-fonts-emoji \
  cups ipp-usb libreoffice-fresh libreoffice-fresh-de krita seahorse freerdp gitg keepassxc pdfpc \
  bluez blueman \
  xdg-desktop-portal xdg-desktop-portal-gtk wine winetricks mpv gpicview qalculate-gtk drawio-desktop code \
  flatpak firefox chromium gnome-keyring virt-manager \
  ghostscript gsfonts foomatic-db-engine foomatic-db foomatic-db-nonfree foomatic-db-ppds foomatic-db-nonfree-ppds gutenprint foomatic-db-gutenprint-ppds hplip \
  cinnamon cinnamon-translations system-config-printer

# enable some services
systemctl enable cups libvirtd.service libvirtd.socket

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

# install obsidian as flatpak
flatpak install --system flathub md.obsidian.Obsidian

# install zen browser as flatpak
flatpak install -y --noninteractive --system flathub app.zen_browser.zen

# set slick greeter as default
sed -i 's/^#\?greeter-show-manual-login=.*/greeter-show-manual-login=true/' /etc/lightdm/lightdm.conf
sed -i 's/^#\?greeter-hide-users=.*/greeter-hide-users=true/' /etc/lightdm/lightdm.conf
sed -i 's/^#\?greeter-session=.*/greeter-session=lightdm-slick-greeter/' /etc/lightdm/lightdm.conf
sed -i 's/^#\?user-session=.*/user-session=cinnamon/' /etc/lightdm/lightdm.conf
sed -i 's/^#\?guest-session=.*/guest-session=cinnamon/' /etc/lightdm/lightdm.conf
sed -i 's/^#\?autologin-session=.*/autologin-session=cinnamon/' /etc/lightdm/lightdm.conf

# configuration for slick-greeter
tee /etc/lightdm/slick-greeter.conf <<EOF
[Greeter]
# LightDM GTK+ Configuration
#
background=/usr/share/backgrounds/elementaryos-default
show-hostname=true
clock-format=%H:%M
EOF

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
oboonakemofpalcgghocfoadofidjkkk
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

# configure cinnamon desktop
mkdir -p /etc/dconf/profile
tee /etc/dconf/profile/user <<EOF
user-db:user
system-db:local
EOF
dconf update

mkdir -p /etc/dconf/db/local.d
tee /etc/dconf/db/local.d/99-userdefaults <<EOF
[org/cinnamon]
favorite-apps=['chromium.desktop', 'firefox.desktop', 'kitty.desktop', 'cinnamon-settings.desktop', 'nemo.desktop']

[org/cinnamon/desktop/background]
picture-uri='file:///usr/share/backgrounds/elementaryos-default'
picture-options='zoom'
primary-color='000000'
secondary-color='000000'
draw-background=true

[org/cinnamon/desktop/interface]
icon-theme='elementary'

[org/cinnamon/desktop/applications/calculator]
exec='qalculate-gtk'

[org/cinnamon/desktop/applications/terminal]
exec='kitty'
exec-arg='--'

[org/cinnamon/desktop/keybindings]
custom-list=['__dummy__', 'custom0', 'custom1', 'custom2', 'custom3', 'custom4']
looking-glass-keybinding=@as []
pointer-next-monitor=@as []
pointer-previous-monitor=@as []
show-desklets=@as []

[org/cinnamon/desktop/keybindings/custom-keybindings/custom0]
binding=['<Shift><Super>Return', '<Shift><Super>KP_Enter']
command='wofi --fork --normal-window --insensitive --allow-images --allow-markup --show drun'
name='wofi'

[org/cinnamon/desktop/keybindings/custom-keybindings/custom1]
binding=['<Super>p', 'XF86Display']
command='arandr'
name='arandr'

[org/cinnamon/desktop/keybindings/custom-keybindings/custom2]
binding=['<Alt>e']
command='kitty /usr/bin/lf'
name='lf'

[org/cinnamon/desktop/keybindings/custom-keybindings/custom3]
binding=['<Alt>w']
command='chromium'
name='chromium'

[org/cinnamon/desktop/keybindings/custom-keybindings/custom4]
binding=['<Control><Shift>e']
command='ibus emoji'
name='emoji picker'

[org/cinnamon/desktop/keybindings/media-keys]
calculator=['<Super>period']
email=@as []
home=['<Super>e']
screensaver=['<Super>l', 'XF86ScreenSaver']
search=@as []
terminal=['<Super>Return', '<Super>KP_Enter']
www=['<Super>w']

[org/cinnamon/desktop/keybindings/wm]
activate-window-menu=@as []
begin-move=@as []
begin-resize=@as []
close=['<Super>q']
move-to-monitor-down=['<Ctrl><Shift><Super>Down']
move-to-monitor-left=['<Ctrl><Shift><Super>Left']
move-to-monitor-right=['<Ctrl><Shift><Super>Right']
move-to-monitor-up=['<Ctrl><Shift><Super>Up']
move-to-workspace-1=['<Shift><Super>1']
move-to-workspace-2=['<Shift><Super>2']
move-to-workspace-3=['<Shift><Super>3']
move-to-workspace-4=['<Shift><Super>4']
move-to-workspace-5=['<Shift><Super>5']
move-to-workspace-6=['<Shift><Super>6']
move-to-workspace-7=['<Shift><Super>7']
move-to-workspace-8=['<Shift><Super>8']
move-to-workspace-9=['<Shift><Super>9']
move-to-workspace-10=@as []
move-to-workspace-11=@as []
move-to-workspace-12=@as []
move-to-workspace-down=['<Shift><Super>Down']
move-to-workspace-left=['<Shift><Super>Left']
move-to-workspace-right=['<Shift><Super>Right']
move-to-workspace-up=['<Shift><Super>Up']
panel-run-dialog=@as []
push-tile-down=['<Ctrl><Super>Down']
push-tile-left=['<Ctrl><Super>Left']
push-tile-right=['<Ctrl><Super>Right']
push-tile-up=['<Ctrl><Super>Up']
show-desktop=@as []
switch-group=@as []
switch-group-backward=@as []
switch-monitor=@as []
switch-panels=@as []
switch-panels-backward=@as []
switch-to-workspace-1=['<Super>1']
switch-to-workspace-2=['<Super>2']
switch-to-workspace-3=['<Super>3']
switch-to-workspace-4=['<Super>4']
switch-to-workspace-5=['<Super>5']
switch-to-workspace-6=['<Super>6']
switch-to-workspace-7=['<Super>7']
switch-to-workspace-8=['<Super>8']
switch-to-workspace-9=['<Super>9']
switch-to-workspace-10=@as []
switch-to-workspace-11=@as []
switch-to-workspace-12=@as []
switch-to-workspace-down=['<Super>Down']
switch-to-workspace-left=['<Super>Left']
switch-to-workspace-right=['<Super>Right']
switch-to-workspace-up=['<Super>Up']
switch-windows=['<Super>Tab']
switch-windows-backward=['<Shift><Super>Tab']
toggle-maximized=['<Super>f']
unmaximize=@as []

[org/cinnamon/settings-daemon/plugins/power]
button-power='shutdown'

[org/cinnamon/muffin]
placement-mode='center'

[org/cinnamon/desktop/wm/preferences]
mouse-button-modifier='<Super>'
EOF
dconf update

# logged in root user dconf session reset
dconf list /org/cinnamon/
dconf reset -f /org/cinnamon/

# set application mimetype defaults
FILELIST=(
  /usr/share/applications/libreoffice-math.desktop
  /usr/share/applications/libreoffice-draw.desktop
  /usr/share/applications/libreoffice-calc.desktop
  /usr/share/applications/libreoffice-writer.desktop
  /usr/share/applications/libreoffice-impress.desktop
  /usr/share/applications/kitty.desktop
  /usr/share/applications/librewolf.desktop
  /usr/share/applications/betterbird.desktop
  /usr/share/applications/engrampa.desktop
  /usr/share/applications/mpv.desktop
  /usr/share/applications/gpicview.desktop
  /usr/share/applications/nemo.desktop
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

# autostart flameshot
mkdir -p /etc/xdg/autostart
tee /etc/xdg/autostart/flameshot.desktop <<EOF
[Desktop Entry]
Name=Flameshot
Comment=Autostart flameshot on startup
Exec=/usr/bin/flameshot
Terminal=false
Type=Application
X-GNOME-Autostart-enabled=true
EOF
chmod +x /etc/xdg/autostart/flameshot.desktop

# autostart gammastep
tee /etc/xdg/autostart/gammastep.desktop <<EOF
[Desktop Entry]
Name=Gammastep
Comment=Autostart gammastep on startup
Exec=/usr/bin/gammastep -l manual:51:10 -t 6500:3500 -b 1:0.75 -m randr
Terminal=false
Type=Application
X-GNOME-Autostart-enabled=true
EOF
chmod +x /etc/xdg/autostart/gammastep.desktop

# autostart ibus environment
tee -a /etc/environment <<EOF
GTK_IM_MODULE=ibus
QT_IM_MODULE=ibus
XMODIFIERS=@im=ibus
EOF
mkdir -p /etc/xdg/autostart
tee /etc/xdg/autostart/ibus-daemon.desktop <<EOF
[Desktop Entry]
Name=IBus
GenericName=Input Method Framework
Comment=Start IBus Input Method Framework
Exec=ibus-daemon -rxR
Icon=ibus
NoDisplay=true
Type=Application
Categories=System;Utility;
EOF
chmod +x /etc/xdg/autostart/ibus-daemon.desktop

# wallpaper switcher service
tee /usr/local/bin/wallpaper.sh <<'EOF'
#!/usr/bin/env bash

WALLPAPER=$( find /usr/share/backgrounds -type f \( -name '*.gif' -o -name '*.png' -o -name '*.jpg' \) | shuf -n 1 )
URLPARSE=$( python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "${WALLPAPER}" )
if [[ "${XDG_CURRENT_DESKTOP}" =~ [Gg]nome ]]; then
  gsettings set org.gnome.desktop.background picture-uri "file://${URLPARSE}"
fi
if [[ "${XDG_CURRENT_DESKTOP}" =~ [Mm]ate ]]; then
  gsettings set org.mate.desktop.background picture-uri "file://${URLPARSE}"
fi
if [[ "${XDG_CURRENT_DESKTOP}" =~ [Cc]innamon ]]; then
  gsettings set org.cinnamon.desktop.background picture-uri "file://${URLPARSE}"
fi
EOF
chmod +x /usr/local/bin/wallpaper.sh
mkdir -p /etc/systemd/user
tee /etc/systemd/user/wallpaper.service << EOF
[Unit]
Description=Switch to random desktop wallpaper

[Service]
Type=simple
StandardInput=null
StandardOutput=journal
StandardError=journal
ExecStart=/usr/local/bin/wallpaper.sh

[Install]
WantedBy=default.target
EOF
tee /etc/systemd/user/wallpaper.timer << EOF
[Unit]
Description=Execute wallpaper switcher service every hour

[Timer]
OnCalendar=hourly
Unit=wallpaper.service

[Install]
WantedBy=timers.target
EOF
systemctl --global enable wallpaper.timer

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

# install code-oss extensions for user"
( HOME=/etc/skel /bin/bash -c '
# csharp
code --install-extension muhammad-sammy.csharp --force
# xml
code --install-extension dotjoshjohnson.xml --force
# better comments
code --install-extension aaron-bond.better-comments --force
# git graph
code --install-extension mhutchie.git-graph --force
# git blame
code --install-extension waderyan.gitblame --force
# yara
code --install-extension infosec-intern.yara --force
# hex editor
code --install-extension ms-vscode.hexeditor --force
# german language pack
code --install-extension ms-ceintl.vscode-language-pack-de --force
# color code highlighter
code --install-extension naumovs.color-highlight --force
' ) &
pid=$!
wait $pid

echo ":: append gnome keyring to pam login"
# see https://wiki.archlinux.org/title/GNOME/Keyring#PAM_step
if [ -f /etc/pam.d/login ]; then
  sed -i 's/auth\s\+include\s\+system-local-login/auth       include      system-local-login\nauth       optional     pam_gnome_keyring.so/' /etc/pam.d/login
  sed -i 's/session\s\+include\s\+system-local-login/session    include      system-local-login\nsession    optional     pam_gnome_keyring.so auto_start/' /etc/pam.d/login
  systemctl --global disable gnome-keyring-daemon.socket
fi
if [ -f /etc/pam.d/passwd ]; then
  sed -i 's/password\s\+include\s\+system-auth/password        include         system-auth\npassword        optional        pam_gnome_keyring.so/' /etc/pam.d/passwd
fi

# cinnamon taskbar shortcuts
mkdir -p /etc/skel/.config/cinnamon/spices/grouped-window-list@cinnamon.org
tee /etc/skel/.config/cinnamon/spices/grouped-window-list@cinnamon.org/2.json <<EOF
{
    "pinned-apps": {
        "type": "generic",
        "default": [
            "nemo.desktop",
            "firefox.desktop",
            "org.gnome.Terminal.desktop"
        ],
        "value": [
            "nemo.desktop",
            "chromium.desktop",
            "firefox.desktop",
            "kitty.desktop",
            "code-oss.desktop",
            "drawio.desktop"
        ]
    },
    "show-apps-order-hotkey": {
        "type": "keybinding",
        "default": "<Super>grave",
        "description": "Global hotkey to show the order of apps",
        "value": ""
    },
    "super-num-hotkeys": {
        "type": "checkbox",
        "default": true,
        "description": "Enable Super+<number> shortcut to switch/open apps",
        "value": false
    }
}
EOF

# configure flameshot
mkdir -p /etc/skel/.config/flameshot
tee /etc/skel/.config/flameshot/flameshot.ini <<'EOF'
[General]
contrastOpacity=188
showStartupLaunchMessage=false
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
[ -f "${0}" ] && rm -- "${0}"
