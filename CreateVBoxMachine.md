# Create VBox Machine

## Basic commands

```
$ VBoxManage createvm --name "${VM}" --ostype "RedHat_64" --register
$ VBoxManage createhd --filename "${DIR}/${VM}.vdi" --size 8000
$ VBoxManage storagectl "${VM}" --name "SATA Controller" --add sata --controller IntelAHCI
$ VBoxManage storageattach "${VM}" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "${DIR}/${VM}.vdi"
$ VBoxManage modifyvm "${VM}" --memory 512 --boot1 disk --boot2 net --boot3 none --boot4 none	--nic1 intnet --intnet1 "lab" --nic2 natnetwork
$ VirtualBox --startvm "${VM}"
```

Without VBox Extension Pack, PXE boot isn't available with e1000 NIC, but it is with PCNet Fast III (TODO: test that). So:

```$ VBoxManage modifyvm "${VM}" --nictype Am79C973```

## Set a property

```
$ VBoxManage guestproperty set "${VM}" $name $value --flags TRANSIENT,RDONLYGUEST 
```

## Install VBox additions

Insert Guest Additions CD with HOST+D shortcut 
TODO: find a command-line for that (see guestcontrol)

```
# mount /dev/sr0 /mnt
# yum -y install gcc kernel-devel-$(uname -r) kernel-headers-$(uname -r) bzip2
# export KERN_DIR=/usr/src/kernels/$(uname -r)
# /mnt/VBoxLinuxGuestAdditions.run
# umount /mnt
# yum -y remove gcc kernel-devel-$(uname -r) kernel-headers-$(uname -r) bzip2

```

## Use VBox TFTP Server 
```
$ VBoxManage modifyvm "${VM}" --nic1 nat --boot4 net
$ cp -R ~/TFTP ~/Library/VirtualBox/
$ ls ~/Library/VirtualBox/TFTP
menu.c32					pxelinux.0		vesamenu.c32
initrd.img-centos7.x86_64	pxelinux.cfg	vmlinuz-centos7.x86_64
$ NICTYPE=e1000
$ VBoxManage setextradata "${VM}" VBoxInternal/Devices/$NICTYPE/0/LUN#0/Config/BootFile pxelinux.0
```
setextradata isn't mandatory: if not set, Vbox will look for a file named after the VM name.

Note: Replace NICTYPE with "pcnet" for PCNet NICs 

## Use VBox internal DHCP server with intnet network

```
$ VBoxManage dhcpserver add --netname lab --netmask 255.255.255.0 --ip 192.168.0.253 --lowerip 192.168.0.10 --upperip 192.168.0.100 --enable
```

## createvm.sh
See [createvm.sh]
