# Make Live CD

## Purpose

This HowTo aims to provide advice on the way to create a bootable Live CD/USB media of RHEL.

## Prerequisites

In order to create the live CD you will need:
* livecd-creator utility, provided by the package livecd-tools (available in Fedora epel repository)
* A kickstart file ([Kickstart How To](https://access.redhat.com/site/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/Installation_Guide/s1-kickstart2-file.html))
* Enough free space, to host the ISO file and mount the live OS for on-the-fly postinstall

## Live image creation

Simply run livecd-creator with the right arguments.

Argument | Value
---------|---------
config|Path to kickstart file
fslabel|Label of the live media
logfile|Path to log of creation
cache|Alternative cache path
tmpdir|Alternative tmp path


Example:
```sh
livecd-creator --verbose --config=./livecd.ks --fslabel="My Uber Live CD" --logfile=./livecdcreation.log --cache=/liveisocache --tmpdir=/liveisotmp
```

## Tips for the KS file

### Include custom files

In the kickstart file, you can include any file you want into the live image. To do so, use --nochroot switch on %post section. If you use the switch, every path in the post section will be using the host filesystem. The 2 following environment variables will have to be used in order to address the live-image filesystem:

 * INSTALL_ROOT : potentially compressed installed OS
 * LIVE_ROOT : root of the media, even if not booted

### Add external rpms

The simplest way to install third party RPMs is to [create a local repository](https://access.redhat.com/site/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/Deployment_Guide/sec-Yum_Repository.html). You will need:

 * createrepo package
 * a dedicated folder with rpms
 
```sh
createrepo --database /path/to/my/folder
```

Then, add a repo to your kickstart file using "repo --name=<reponame>" option with baseurl=file:/path/to/my/folder

### Bugs

No idea why, but with the "quiet" argument in grub the OS never managed to boot. To remove this option completely, here a snippet from the %post section of the KS file:
```sh
for modif in BOOT.conf BOOTIA32.conf grub.conf isolinux.cfg; do
	sed -i -e 's/ quiet//g' $LIVE_ROOT/EFI/BOOT/$modif
done
sed -i -e 's/ quiet//g' $LIVE_ROOT/isolinux/isolinux.cfg
```

### Put it on a USB stick
```
dd if=/path/to/image.iso of=/dev/myusb
```

## makelivecd.sh

```sh
#!/bin/bash

KSFILE=$1
FSLABEL=$2
LOG=./makelivecd.log

livecd-creator --verbose --config="$KSFILE" --fslabel="$FSLABEL" --logfile="$LOG" --cache=/liveiso --tmpdir=/liveisotmp
```

## KS file example

```
lang C
keyboard fr
rootpw --plaintext root
services --disable=sshd
timezone Europe/Paris
selinux --enforcing
firewall --enabled --service=mdns
skipx
bootloader --timeout=3
firstboot --disabled

repo --name=released --baseurl=http://example.com/distribution/linux/as-6-u4-i686
repo --name=local --baseurl=file:/root/myrepo

%packages
@core
@base
wget
%end

%post --erroronfail --log=/root/ks.log --nochroot

cp -R /root/tools $INSTALL_ROOT/tools

for modif in BOOT.conf BOOTIA32.conf grub.conf isolinux.cfg; do
        sed -i -e 's/ quiet//g' $LIVE_ROOT/EFI/BOOT/$modif
done
sed -i -e 's/ quiet//g' $LIVE_ROOT/isolinux/isolinux.cfg

echo 'export PATH=$PATH:/tools' >>$INSTALL_ROOT/etc/profile.d/custom.sh

%end
```
