#!/bin/bash
#==================================================
# Source of Information
# https://wiki.ubuntu.com/KernelTeam/GitKernelBuild
#==================================================
modules=(kvmgt vfio-iommu-type1 vfio-mdev vfio-pci)

for i in "${modules[@]}"
  do
    echo $i
sudo -s <<RUNASSUDO_MODULES
    grep -qxF $i /etc/initramfs-tools/modules || echo $i >> /etc/initramfs-tools/modules
RUNASSUDO_MODULES
done
