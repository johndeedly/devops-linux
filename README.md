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
- **📁database** - a temporary folder for package and installation image caching, allowing for installations where no internet is available e.g. to use a local package cache from previous installations
- **📁output** - the final artifacts are placed inside this folder
- **📁output/📁artifacts/📁audit** - when running an audit, the results are placed here
- **📁output/📁artifacts/📁docker** - the produced docker image is placed here
- **📁output/📁artifacts/📁liveiso** - when building the archiso or debiso livecd, the resulting *.iso is placed here
- **📁output/📁artifacts/📁pxe** - the produced files for pxe booting are placed here
- **📁output/📁artifacts/📁tar** - when building a disk dump image for lxc container usage, the resulting compressed tar is placed here
- **📁output/📁devops-linux** - the produced virtual machine is placed here
- **📁output/📁devops-linux/📁vtpm.0** - when executing qemu typically with uefi bios, the state of the swtpm is placed into this folder
- **📁output/📁devops-linux/📄devops-linux-x86_64.run.sh** - the main executable script for the produced virtual machine
- **📁output/📁devops-linux/📄devops-linux-x86_64.gl.sh** - the same as the ".run.sh" version, including support for graphic acceleration (**only** gpu accel, so expect a black screen on bootup)
- **📁output/📁devops-linux/📄devops-linux-x86_64.netdev.sh** - starts qemu with an additional nic listening on a socket for later pxe clients
- **📁output/📁devops-linux/📄devops-linux-x86_64.pxe.sh** - test pxe booting prebuild images, connecting to the *.netdev.sh router
- **📁output/📁devops-linux/📄devops-linux-x86_64.srv.sh** - the same as run, just without any gpu attached to run as a background process
- **📁output/📁devops-linux/📄efivars.fd** - when executing qemu typically with uefi bios, the last state of the nvram is placed here
- **📄cidata.sh** - preparation script to package the files needed for CIDATA execution of cloud-init
  | long | short | description |
  |---|-|------|
  | --archiso | -a | Mutually exclusive to --archiso: generates a CIDATA datasource *.iso, **with** the devops-linux installation stack based on ArchISO (Arch Linux or Debian). You can pass this to both VMs and baremetal systems. |
  | --iso | -i | Mutually exclusive to --archiso: generates a CIDATA datasource *.iso, **without** the devops-linux installation stack based on ArchISO (Arch Linux or Debian). This can be used in situations, where you boot directly into a cloud image vm without any preparations. This mode is not tested at all, so you may find unicorns or other magical beings ahead... |
  | --isoinram | -r | Used typically inside the pipeline.sh script to build the devops linux installation medium for one quick build job inside the RAM to reduce stress on solid state drives. |
  | --no-autoreboot | -n | The default option for non packer builds. When packer is not there to download logs and control the reboot process, a restart script is placed into the build job to remove the need for user interaction at the end of each stage. |
  | --proxmox | -p | Quickly generate an ArchISO image including a ready-to-run devops linux installation VM on Proxmox based on the given setup instructions. |
  | --pxe | -e | Legacy option: to produce a PXE bootable version of the devops linux stack, this option extracts the kernel and initramfs of the installation medium including the syslinux configuration into "archiso_pxe-linux.tar.zst". Afterwards, the only thing left is to extract it to your TFTP server of choice and tell it where to find the CIDATA source through the "ds=" kernel parameter. This is now considered deprecated, as the main focus lies now on grub, letting it boot into ArchISOs and Debian LiveCDs directly without the need to extract or build anything. |
- **📄pipeline.sh** - this script will start the whole setup pipeline
  | long | short | description |
  |---|-|------|
  | --show-window | -w | Executes a headful build run, showing the QEMU or VirtualBox window in the process. Great for debugging purposes. |
  | --force-virtualbox | -v | Either on Linux or alternatively on Windows inside a msys2 environment, too, you can force the usage of VirtualBox to execute the devops build process. |
  | --create-cache | -c | Uses the **📁database** directory to (re-)store the package cache or cloud images of each distro, accelerating the build process. |

Supported cloud images are Arch, Ubuntu, Debian and Rocky Linux, although Rocky is not well tested, as I mainly utilize Arch for clients and Debian for servers.

## Config File Structure

**📁config/📄setup.yml**
```yaml
## setup instructions
setup:
  ## chosen distro name
  distro: [...]
    ## this special value tells the build chain that you want to write a ready-to-run devops-linux QCOW2 image onto the target disk
    - dump
  ## execute additional build pipelines based on the selected options
  options:
    - [...]
  ## the path to the target device to write the cloud image onto. "auto" tries to find a hard drive on it's own, but errors out when nothing is found.
  target: [...]
    ## Automatically chooses the target device based on typical first virtual or physical installation candidates (/dev/vda, /dev/nvme0n1, /dev/sda). Will as a security measure stop the installation when data is already on the disk, preventing the accidental destruction of an existing os.
    - auto
    ## Let the user choose which target to install to. Open a browser and point it to http://[setup-ip]:5000/. Alternatively, when the log message appears, press enter, log into the box using the default credentials "user/resu", type "curl localhost:5000" to retrieve a list of candidates and "curl -X POST localhost:5000 -d disk=/dev/vda" to select a target
    - select
    ## When "auto" does not work or you know what you are doing, give the setup a predefined target to install to
    - /path/to/device
  ## the fqdn hostname of the produced os
  hostname: ""
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
  ## when building an authentication server with ldap, provide the setup with the necessary informations for your domain (here: *.lan.internal)
  authserver:
    ## the base DC without the TLD part
    base_dc: lan
    ## the full DN including the TLD part
    base_dn: dc=lan,dc=internal
    ## the OU for the groups definition (Groups is LDAP standard)
    group_ou: Groups
    ## the full DN to identify the groups OU
    group_dn: ou=Groups,dc=lan,dc=internal
    ## the OU for the users definition (People is LDAP standard)
    user_ou: People
    ## the full DN to identify the users OU
    user_dn: ou=People,dc=lan,dc=internal
    ## the CN for the admin account (Manager is LDAP standard)
    mgmt_cn: Manager
    ## the full DN to identify the admin account that can directly modify the LDAP directory
    mgmt_dn: cn=Manager,dc=lan,dc=internal
  ## remote logging to a syslog daemon
  remote_log:
    ## enable the remote logging
    enabled: false
    ## set the ip or fqdn to the remote server
    syslog_server: 0.0.0.0
    ## set the server port (the defaults are: 514 unencrypted, 6514 encrypted)
    syslog_port: 514
    ## set the connection x509 key (leave empty for no tls encryption)
    x509_key: ""
    ## set the connection x509 certificate (leave empty for no tls encryption)
    x509_crt: ""
    ## set the certificate verification mode (leave empty for no tls encryption)
    ## accepted values: optional-trusted, optional-untrusted, required-trusted, required-untrusted, yes, no
    peer_verify: ""
    ## sha1 hash of the certificate in the form SHA1:AA:BB:CC:DD:...
    x509_hash: ""
  logserver:
    ## the keys can be gernerated with the following command:
    ##   $) openssl req -x509 -newkey ed25519 -days 36500 -noenc -keyout internal.key \
    ##      -out internal.crt -subj "/CN=internal" -addext "subjectAltName=DNS:internal,DNS:*.internal"
    logfile: /var/log/remote.log
    ## set the ip the server binds to (0.0.0.0 means all interfaces, IPv6 is not supported)
    bind_ip: 0.0.0.0
    ## set the port the server binds to (the defaults are: 514 unencrypted, 6514 encrypted)
    bind_port: 6514
    ## set the connection x509 key (leave empty for no tls encryption)
    x509_key: ""
    ## set the connection x509 certificate (leave empty for no tls encryption)
    x509_crt: ""
    ## set the certificate verification mode (leave empty for no tls encryption)
    ## accepted values: optional-trusted, optional-untrusted, required-trusted, required-untrusted, yes, no
    peer_verify: ""
    ## sha1 hash of the certificate in the form SHA1:AA:BB:CC:DD:...
    x509_hash: ""
  ## set the package mirror based on the ".setup.distro" yaml value (except for archiso)
  pkg_mirror:
    ## the placeholder "##ARCHISO_DATE##" will be replaced at runtime with the corresponding date of the ArchISO setup medium
    archiso: [...]
    ## the content you place here needs to fit the config format of the underlying package manager
    ## e.g. Arch Linux needs something in the form of "Server = http://.../$repo/os/$arch"
    archlinux: [...]
    debian-13: [...]
    [...]
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
## Mapping distros to their packaging tools (debian -> apt, rocky -> yum, ...)
distros:
  [...]
## Where to download the corresponding qcow2 image
## "archiso" is an exception as the entry maps to the Arch ISO download link
download:
  [...]
## The file name of the downloaded image
images:
  [...]
## setup files per stage and packaging tool
## format: [packaging tool] -> [setup name] -> [path/stage/config file]
files:
  [...]
```

At this point the following options can be selected for installation:

- **graphical-base** (_all_): Install the graphics drivers for the most common virtual and physical GPUs. Probably needed for the desktop environments.
- **mirror** (_all_): Local mirrors for all supported distributions, downloading updates every couple of days for all the packages while keeping the last two or more versions accessible. Instead of using the official default route, we iterate over all available packages, retrieve the download urls and instead of using apt or pacman for the job we download all packages through wget, allowing to timestamp every file and force "304 Not Modified" messages. This method is so much faster and more efficient than the throttled and overrun rsync connections and allows for local repositories that are not officially supported by the vendor.
- **kde** (_Arch, Debian, Ubuntu_): Install the fully configured [kde plasma](https://kde.org/de/plasma-desktop/) desktop, including some default kde applications, excluding unneeded utilities like "plasma-welcome", "kongress", "kteatime" and such.
- **cosmic** (_Arch_): Install the fully configured [cosmic](https://github.com/pop-os/cosmic-epoch) desktop, including graphical tools like office programs, video players, etc.
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
- **archiso** (_Arch_): Instead of relying on an active internet connection, the off-the-shelf ArchISO is rebuild to have every program that needs to be live-installed during runtime be preinstalled. This is usually the first task you need to execute on a freshly downloaded build chain.
- **debiso** (_Debian_): Generate a feature-complete Debian LiveCD installation medium, that can be live booted like an ArchISO, have the same programs and drivers as an ArchISO and can be equally used to build everything out of the devops-linux repository. When you are in need of a different flavour than Arch Linux, use this. It is neither faster nor more secure in comparison to the rebuilded ArchISO version.

## Common Setups (by me)

### Setup #1: PXE, TAR or Podman image of the ready-to-run basic devops-linux
```yaml
setup:
  distro: archlinux
  options:
    - pxe-image

setup:
  distro: debian
  options:
    - tar-image

setup:
  distro: ubuntu
  options:
    - podman-image
```

### Setup #2: Router to host the pxe image produced by #1 for testing
```yaml
## step 1: PXE image
setup:
  distro: archlinux
  options:
    - pxe-image
## step 2: router to host the generated image
setup:
  distro: debian
  options:
    - router
## step 3: mount -t 9p artifacts.0 /mnt && cp /mnt/pxe/arch/x86_64/* /srv/pxe/arch/x86_64/
```

### Setup #3: All-in-one Proxmox including cluster setup and a provisioned jellyfin server
```yaml
## ./pipeline.sh
setup:
  distro: debian
  options:
    - podman
    - jellyfin
## move the resulting 📁output/📁devops-linux/📄devops-linux-*.qcow2
## to 📁database/📄debian-podman-jellyfin-x86_64.qcow2

## the next step is to integrate the qcow2 into a ready to run Proxmox VM
## ./pipeline.sh
setup:
  distro: debian
  options:
    - graphical-base
    - proxmox
    - proxmox-cluster-master
    - proxmox-devops
  proxmox_devops:
    qms:
      - image: debian-podman-jellyfin-x86_64.qcow2
        id: 300
        name: debian-podman-jellyfin
        cores: 4
        memory: 16384
        storage: local
        networks:
          - name: net0
            bridge: vmbr0
            vlan: 0
        ostype: l26
        pool: pool0
        onboot: 1
        reboot: 1
## move the resulting 📁output/📁devops-linux/📄devops-linux-*.qcow2
## to 📁database/proxmox-podman-jellyfin-x86_64.qcow2

## now generate the installation iso to dump the qcow2 content onto any baremetal server or VM you want
## ./cidata.sh --archiso
setup:
  distro: dump
  target: select
download:
  dump: http://0.0.0.0/proxmox-podman-jellyfin-x86_64.qcow2
images:
  dump: proxmox-podman-jellyfin-x86_64.qcow2
```

### Setup #4: Local package mirrors
```yaml
setup:
  distro: archlinux
  options:
    - mirror

setup:
  distro: debian
  options:
    - mirror

setup:
  distro: ubuntu
  options:
    - mirror
```

### Setup #5: Archlinux or Debian with GPU drivers and KDE or Cosmic desktop configured
```yaml
## Use *.gl.sh for gpu acceleration. Keep in mind that you see a black screen until
## the very first graphical backend is initialized (i.e. LightDM). After a VM reboot,
## this odd behaviour does not occur again for some reason.
setup:
  distro: debian
  options:
    - graphical-base
    - kde

setup:
  distro: archlinux
  options:
    - graphical-base
    - cosmic
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

## License

Licensed under the [0BSD](LICENSE.txt) license.