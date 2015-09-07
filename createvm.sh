#!/bin/bash -eux -o pipefail                                                                                                                                                         

NAME=$1
ROLE=$2

VBOX=$(which VBoxManage)

HDDDIR="${HOME}/VirtualboxHDDs/"
NICTYPE=e1000
PXEFILE=pxelinux.0

$VBOX createvm --name "${NAME}" --ostype "RedHat_64" --register
$VBOX createhd --filename "${HDDDIR}/${NAME}.vdi" --size 8000
$VBOX storagectl "${NAME}" --name "IDE Controller" --add ide --controller PIIX4
$VBOX storageattach "${NAME}" --storagectl "IDE Controller" --port 0 --device 0 --type hdd --medium "${HDDDIR}/${NAME}.vdi"

$VBOX modifyvm "${NAME}" --memory 512 
$VBOX modifyvm "${NAME}" --boot1 disk --boot2 net --boot3 none --boot4 none
$VBOX modifyvm "${NAME}" --nic1 nat --nictype1 82543GC 
$VBOX modifyvm "${NAME}" --nic2 intnet --intnet2 lab --nictype2 82543GC 

$VBOX setextradata "${NAME}" "VBoxInternal/Devices/$NICTYPE/0/LUN#0/Config/BootFile" $PXEFILE
$VBOX guestproperty set "${NAME}" role "${ROLE}" --flags TRANSIENT,RDONLYGUEST
$VBOX guestproperty set "${NAME}" hostname "${NAME}" --flags TRANSIENT,RDONLYGUEST

$VBOX startvm "${NAME}"
