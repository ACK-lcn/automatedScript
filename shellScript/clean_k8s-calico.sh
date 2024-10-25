#!/bin/bash
 yum -y remove docker-ce* && yum -y remove kubelet* kubeadm* kubectl*

#remove kubernetes dir
rm -rf /etc/kubernetes

#remove docker storage
rm -rf /var/lib/docker/*

 # calico
ifconfig vxlan.calico down
ip link delete vxlan.calico

# canal
ifconfig tunl0 down
ip link delete tunl0
rm -rf /var/lib/cni/
rm -f /etc/cni/net.d/*
modprobe -r ipip

#remove cni and containerd dir
rm -rf /opt/cni
rm -rf /opt/containerd

#查看是否存在cni文件
ls -l /etc/cni/net.d/

modprobe br_netfilter

ls /proc/sys/net/bridge

echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
echo "net.bridge.bridge-nf-call-iptables = 1" >> /etc/sysctl.conf
echo "net.bridge.bridge-nf-call-ip6tables = 1" >> /etc/sysctl.conf

sysctl -p

#yum -y localinstall *.rpm --skip-broken

sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

#stop server
systemctl stop firewalld && systemctl disable firewalld && systemctl stop NetworkManager && systemctl disable NetworkManager

# reboot 主机
reboot