#!/bin/bash
#writer: ACK

#Environment variable
nouveau_file="/etc/modprobe.d/blacklist-nouveau.conf"

#check blacklist-noveau.conf
if [[ ! -f $nouveau_file ]];then
   echo "blacklist nouveau" >> $nouveau_file
   echo "modeset options=0" >> $nouveau_file
else
   echo "blacklist-nouveau.conf File already exists, Please ignore ..."
fi

#Construct initramfs and dracut initramfs
mv /boot/initramfs-$(uname -r).img /boot/initramfs-$(uname -r).img.bak && dracut /boot/initramfs-$(uname -r).img $(uname -r)

if [ $? -ne 0 ];then
   echo "Construct initramfs and dracut initramfs carried out failed ..."
else
   echo "Construct initramfs and dracut initramfs carried out succeed ..."
fi

# reboot system
echo "reboot system"

reboot