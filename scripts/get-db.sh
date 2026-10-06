#!/bin/bash

source scripts/utils.sh

# Script to generate DB dataset.

chmod +x scripts/db.rc.local
mkdir -p "$DATA_PATH/db"
cd "$DATA_PATH/db" || exit

rm -f *.qcow2
wget -nc -q https://cloud.debian.org/images/cloud/bookworm/20250210-2019/debian-12-nocloud-amd64-20250210-2019.qcow2

echo "Creating base image"
qemu-img create -f qcow2 -F qcow2 -b debian-12-nocloud-amd64-20250210-2019.qcow2 root.qcow2 100g
virt-customize -a root.qcow2 --copy-in ../../scripts/db.rc.local:/etc/
virt-customize -a root.qcow2 --run-command "mv /etc/db.rc.local /etc/rc.local"

echo 1
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "1.qcow2"

echo 2
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "2.qcow2"

echo 3
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "3.qcow2"

echo 4
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "4.qcow2"

echo 5
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "5.qcow2"

echo 6
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "6.qcow2"

echo 7
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "7.qcow2"

echo 8
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "8.qcow2"

echo 9
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "9.qcow2"

echo 10
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "10.qcow2"

echo 11
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "11.qcow2"

echo 12
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "12.qcow2"

echo 13
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "13.qcow2"

echo 14
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "14.qcow2"

echo 15
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "15.qcow2"

echo 16
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "16.qcow2"

echo 17
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "17.qcow2"

echo 18
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "18.qcow2"

echo 19
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "19.qcow2"

echo 20
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "20.qcow2"

echo 21
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "21.qcow2"

echo 22
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "22.qcow2"

echo 23
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "23.qcow2"

echo 24
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "24.qcow2"

echo 25
qemu-system-x86_64 -m 4g \
		-enable-kvm  \
		-nographic \
		-serial mon:stdio \
		-drive file=root.qcow2,driver=qcow2 \
		-nic user,model=virtio-net-pci
cp root.qcow2 "25.qcow2"

rm debian-12-nocloud-amd64-20250210-2019.qcow2 root.qcow2
