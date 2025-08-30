# DevOps Linux
    
![Linux server in a container](devops.png) Build once, deploy everywhere, as easy as cake!

## Repository

This source code is available to everyone under the standard [0BSD License](LICENSE.txt) to allow every setup configuration in every way possible, commercial background or not. Some of the scripts in this project **will** destroy all data on your system. So be careful and use a testing lab first! Common sense, people. **I will not take any responsibility for any of your lost files!**

## Build Environment

Your build environment should include the following programs:
- **packer** for automation,
- **swtpm** for TPM emulation,
- **cloud-image-utils** to package the complete build chain into a single mime-multipart user-data file,
- **xorriso** to repackage the Arch ISO,
- **yq** for config file parsing, and
- **qemu-desktop** (Arch) / **qemu-system-x86_64** (Debian/Ubuntu) for virtualization.

The project has the following folder structure:
- **📁build** - in this folder all the files are prepared before they are placed inside the Arch ISO
- **📁config** - the main folder containing all the python, setup and config files
- **📁config/📄setup.yml** - central configuration file describing all the files that are needed for the installation
- **📁database** - a temporary folder for package caching, allowing for installations where no internet is available to use a local package cache from previous installations
- **📁output** - the final artifacts are placed inside this folder
- **📁output/📁artifacts/📁docker** - the produced docker image is placed here
- **📁output/📁artifacts/📁pxe** - the produced files for pxe booting are placed here
- **📁output/📁devops-linux** - the produced virtual machine is placed here
- **📁output/📁devops-linux/📄devops-linux-x86_64.run.sh** - the main executable script for the produced virtual machine
- **📁output/📁devops-linux/📄devops-linux-x86_64.gl.sh** - the same as the ".run.sh" version, including support for graphic acceleration (**only** gpu accel, so expect a black screen on bootup)
- **📁output/📁devops-linux/📄devops-linux-x86_64.pxe.sh** - test pxe booting the router build provided image (after adding an additional socket netdev to ".run.sh")
- **📄cidata.sh** - preparation script to package the files needed for CIDATA execution of cloud-init
- **📄pipeline.sh** - this script will start the whole setup pipeline

Supported cloud images are Arch, Ubuntu, Debian and Rocky Linux, although Rocky is not well tested, as I mainly utilize Arch for clients and Debian for servers.

## Config File Structure

**📁config/📄setup.yml**
```yaml
## Mapping distros to their packaging tools (debian -> apt, rocky -> yum, ...)
distros:
  [...]
## Where to download the corresponding qcow2 image
## "archiso" is an exception as the entry maps to the Arch ISO download link
download:
  [...]
## End of life for all the distro package versions. Will print an error and abort the setup
## when no support is to be expected from the maintainers any more.
endoflife:
  [...]
## The file name of the downloaded image
images:
  [...]
## setup files per stage and packaging tool
## format: [packaging tool] -> [setup name] -> [path/stage/config file]
files:
  [...]
## setup instructions
setup:
  ## chosen distro name
  distro: [...]
  ## which files to install via setup name and distro
  options:
    - [...]
  ## the path to the target device to write the cloud image onto. "auto" tries to find a hard drive on it's own, but errors out when nothing is found.
  target: auto
  ## utilize a tar image placed inside the database folder as encrypted root filesystem
  encrypt:
    ## enable the encrypt build
    enabled: false
    ## password for luks encrypted drive
    password: packer-build-passwd
    ## the image inside the database folder to use
    image: devops-linux-archlinux.tar.zst
  ## connect the provisioned system to a local ldap server for authentication (uses defaults of authserver build)
  ldapauth:
    ## enable the ldap setup
    enabled: false
    ## ldap endpoint
    authserver: ldap://0.0.0.0/
    ## base group
    base: dc=internal
    ## selector for auth groups
    group: ou=Groups,dc=internal
    ## selector for auth users
    passwd: ou=People,dc=internal
    ## selector for auth password (typically the same as the user selector, as the password is stored on the user entry)
    shadow: ou=People,dc=internal
  ## (local) mirror link to the base of archive.archlinux.org
  archiso_mirror: false
  ## (local) package mirror link
  pkg_mirror: false
  ## proxmox cluster setup (one master and many workers)
  proxmox_cluster:
    ## the keys are generated through the command
    ##   $) ssh-keygen -q -N "" -C "root" -t ed25519 -f ssh_host_cluster_key
    ## the private key will be placed on all worker instances
    cluster_key: |
      -----BEGIN OPENSSH PRIVATE KEY-----
      [...]
      -----END OPENSSH PRIVATE KEY-----
    ## the public key is placed on both the master and the worker instances
    cluster_pub: |
      ssh-ed25519 [...] root
    ## either put an ip to the master node here or leave it empty to
    ## activate the broadcast logic
    master_ip: ""
    ## port opened on the master to receive the broadcast messages
    broadcast_port_master: 17789
    ## port opened on the worker instances to send the echo request
    broadcast_port_worker: 17790
    ## only broadcast in this ip range
    broadcast_range: 0.0.0.0/0
```

At this point the following options can be selected for installation:

- **base** (_all_): Some programs installed for ease of use, performing most of the tasks inside the terminal. The graphics drivers for the most common (virtual) GPUs are placed here, too. They are not needed for the essential basics.
- **mirror** (_all_): Local mirrors for all supported distributions, downloading updates every couple of days for all the packages while keeping the last two or more versions accessible. Instead of using the official default route, we iterate over all available packages, retrieve the download urls and instead of using apt or pacman for the job we download all packages through wget, allowing to timestamp every file and force "304 Not Modified" messages. This method is so much faster and more efficient than the throttled and overrun rsync connections and allows for local repositories that are not officially supported by the vendor.
- **cinnamon** (_Arch_): Install the fully configured [cinnamon](https://github.com/linuxmint/cinnamon) desktop, including graphical tools like office programs, video players, etc.
- **kde** (_Arch, Debian, Ubuntu_): Install the fully configured [kde plasma](https://kde.org/de/plasma-desktop/) desktop, including some default kde applications, excluding unneeded utilities like "plasma-welcome", "kongress", "kteatime" and such.
- **podman** (_Arch, Debian, Ubuntu_): A docker replacement, that is fully compatible with all commands and hubs, and the new modern way to handle containers. In addition, [portainer](https://www.portainer.io/) is installed for easy container management via browser.
- **postgres** (_Arch, Debian, Ubuntu_): Install [postgres](https://www.postgresql.org/) as a container.
- **homeassistant** (_Arch, Debian, Ubuntu_): Install [homeassistant](https://www.home-assistant.io/) as a container.
- **cronicle** (_Arch, Debian, Ubuntu_): Install [cronicle](https://github.com/jhuckaby/Cronicle) as a container.
- **dagu** (_Arch, Debian, Ubuntu_): Install [dagu](https://github.com/dagu-org/dagu) as a container.
- **plex** (_Arch, Debian, Ubuntu_): Install [plex media server](https://www.plex.tv/) as a container including shared gpu passthrough and configuration of the host.
- **jellyfin** (_Arch, Debian, Ubuntu_): Install [jellyfin](https://jellyfin.org/) as a container including shared gpu passthrough and configuration of the host.
- **minecraft-cobblemon** (_Arch, Debian, Ubuntu_): Install [minecraft](https://www.minecraft.net/de-de) as a container with preconfigured cobblemon mod.
- **minecraft-create** (_Arch, Debian, Ubuntu_): Install [minecraft](https://www.minecraft.net/de-de) as a container with preconfigured create mod.
- **cicd** (_Arch, Debian, Ubuntu_): Create some preconfigured ISOs to download and install DevOps-Linux with.
- **gitlab** (_Arch, Debian, Ubuntu_): Install [gitlab](https://about.gitlab.com/) as a container.
- **router** (_Arch_): A fully functional virtual router with DHCP4, DHCP6, DNS, NTP, PXE boot and ACME certificate authority. Connect the router through ```-netdev socket,listen=...``` with subsequent virtual machines ```-netdev socket,connect=...```. To arm PXE boot with the prebuild initramfs, kernel and image, the ```📁output/📁artifacts``` folder in the default configuration can be mounted via ```mount -t 9p artifacts.0 /mnt``` and the contents then copied to ```cp /mnt/pxe/arch/x86_64/* /srv/pxe/arch/x86_64/```.
- **proxmox** (_Debian_): Install [proxmox](https://www.proxmox.com/en/) to configure and spawn virtual machines and LXC container via gui.
- **podman-image** (_Arch, Debian_): As the final step, take everything that was configured before and generate a fully functional OCI container, that can be uploaded to any docker or podman instance.
- **pxe-image** (_Arch, Debian, Ubuntu_): As the final step, take everything that was configured before and generate a fully functional pxe boot image, that can e.g. be used in conjunction with the router option above to netboot any device on the LAN. The Arch PXE image is able to be booted via CIFS, HTTP, ISCSI, NBD, NFS, NVMEOF and SCP, the Debian and Ubuntu images only via CIFS, HTTP and NFS (more to come).
- **tar-image** (_Arch, Debian, Ubuntu_): As the final step, take everything that was configured before and generate a fully functional LXC container image, that can be uploaded to any proxmox instance.

## Common Setups (by me)

### Setup #1: PXE image with kde and basic tools
```yaml
setup:
  distro: archlinux
  options:
    - base
    - kde
    - pxe-image
```

### Setup #2: Router to host the pxe image produced by #1 for testing
```yaml
setup:
  distro: archlinux
  options:
    - base
    - router
```

### Setup #3: Proxmox server
```yaml
setup:
  distro: debian
  options:
    - base
    - proxmox
```

### Setup #4: Archlinux and Debian local mirror
```yaml
setup:
  distro: archlinux
  options:
    - mirror

setup:
  distro: debian
  options:
    - mirror
```

### Setup #5: Build a minimal Arch Linux or Debian container 
```yaml
setup:
  distro: archlinux
  options:
    - podman-image

setup:
  distro: debian
  options:
    - podman-image
```

### Setup #6: Podman server to host dagu for automation
```yaml
setup:
  distro: debian
  options:
    - base
    - podman
    - dagu
```

## Boot DevOps Linux Setup via PXE (Network Install)

### Basic components needed

- PXE capable DHCP server (e.g. _Setup #2_)
- HTTP server (e.g. _Setup #2_, too)
- The modified ArchISO image containing the cloud init config files

### Configuration steps

- Mount the ArchISO image to access it's files:
  - In most distros inside a graphical environment you just need to doubleclick the file
  - Inside a shell you create a folder and mount the iso: ```mkdir -p /mnt/iso; mount -o loop,ro archlinux-x86_64-cidata.iso /mnt/iso```
- Five files are needed:
  | Path on CD | Purpose | Target Location (when _Setup #2_ is used) | Remarks |
  |--|---|--|-|
  | arch/boot/x86_64/vmlinuz-linux | The ArchISO kernel | /srv/pxe/__arch/x86_64/vmlinuz-linux__ | |
  | arch/boot/x86_64/initramfs-linux.img | The ArchISO minimal ramdisk | /srv/pxe/__arch/x86_64/initramfs-linux.img__ | |
  | arch/x86_64/airootfs.sfs | The root filesystem (squashfs) | /srv/pxe/__arch/x86_64/airootfs.sfs__ | |
  | meta-data | Cloud Init meta data (probably just an empty file) | /srv/pxe/__config/meta-data__ | The path to ```/srv/pxe/config``` probably needs to be created |
  | user-data | Cloud Init user data (the whole DevOps-Linux setup, packaged as ```Content-Type: multipart/mixed```) | /srv/pxe/__config/user-data__ | The path to ```/srv/pxe/config``` probably needs to be created |
- Modify the ```/srv/tftp/pxelinux.cfg/default``` (_Setup #2_) bootmenu file
  ```
  UI menu.c32
  SERIAL 0 115200
  PROMPT 0
  TIMEOUT 150
  ONTIMEOUT DevOpsHTTP
  
  MENU TITLE DevOps-Linux PXE Installation
  
  MENU CLEAR
  MENU IMMEDIATE
  
  LABEL DevOpsHTTP
  MENU LABEL DevOps-Linux PXE Installation using HTTP
  LINUX http://10.42.42.42/arch/x86_64/vmlinuz-linux
  INITRD http://10.42.42.42/arch/x86_64/initramfs-linux.img
  APPEND archiso_pxe_http=http://10.42.42.42/ cow_spacesize=75% ds=nocloud;s=http://10.42.42.42/config/ console=tty1 rw loglevel=3 acpi=force acpi_osi=Linux
  SYSAPPEND 3
  ```

### Common Gotchas

- Did you check the access rights for the ```/srv/pxe/*``` subfolders and files? The folders are owned by ```root```, probably. As non-root users need to access the files, too, the folders need ```rwxr-xr-x``` (```0755```) permission and the files ```rw-r--r--``` (```0644```). A quick fix would be the following code snippet:
  ```bash
  find /srv/pxe -type d -print | while read -r line; do
    chmod 0755 "$line"
  done
  find /srv/pxe -type f -print | while read -r line; do
    chmod 0644 "$line"
  done
  ```
- The package cache that is placed in the ```database/``` folder on the ArchISO cannot be used with this method. You either need to configure a package mirror as described in _Setup #4_ and configure your sources, or skip caching completely.

## License

Licensed under the [0BSD](LICENSE.txt) license.