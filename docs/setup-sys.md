# Folder structure
```
sudo mkdir -p /var/vm
sudo mkdir -p /var/vm/disk
sudo mkdir -p /var/vm/fw
sudo mkdir -p /var/vm/iso
sudo mkdir -p /var/vm/scripts
sudo mkdir -p /var/vm/cfg
sudo mkdir -p /var/vm/docs
sudo mkdir -p /var/vm/systemd
```
# Setting up base OS, permissions and environment

Once we have the kernel compiled, we can proceed to set up base OS.

## Modules configuration

The first step we must do is to ensure the right modules are loaded with this kernel early inside initrd. The key modules that must be loaded are:
* kvmgt
* vfio-iommu-type1
* vfio-mdev
* vfio-pci

Use the following instructions to automate this process.

```
chmod +x setup/setup-modules.sh
bash -x ./setup/setup-modules.sh
sudo update-initramfs -u
```
## Install and configure qemu
```
mkdir -p /tmp/qemu
unzip qemu.zip -d /tmp/qemu/
mv /tmp/qemu/bios.bin
## Install and configure kernel

Then we can install the kernel.
```
cd /home/user/buildfolder
sudo dpkg -i linux-image-*.deb linux-headers-*.deb
```
Before rebooting the system, we need to make sure this new kernel is used as default and the right kernel options are turned on. This can be done by modifying Grub configuration (/etc/default/grub)

```
sudo nano /etc/default/grub
```

Here are the GRUB entries for debugging.

```
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=-1
GRUB_CMDLINE_LINUX_DEFAULT="splash quiet i915.enable_gvt=1 i915.enable_fbc=0 kvm.ignore_msrs=1 intel_iommu=on,igfx_off drm.debug=0"
```

Here are they key entries for production that you need to update. Adjust kernel version ( in this case 5.4.54-intelgvt+) to the version of the your kernel.

```
GRUB_DEFAULT="Advanced options for Ubuntu>Ubuntu, with Linux 5.4.54-intelgvt+"
GRUB_CMDLINE_LINUX_DEFAULT="splash quiet i915.enable_gvt=1 i915.enable_fbc=0 kvm.ignore_msrs=1 intel_iommu=on,igfx_off drm.debug=0"
```

The next step will be to update Grub
```
sudo update-grub2
```
## Setting up subsystem with the right permission

Running guest VM as root is not preferred. The recommended way is to only allow certain group to have that right. Typically for KVM hypervisor, the group name is 'kvm'. Thus the recommended is to add the designated user to 'kvm' group. Other privilege such as serial port ownership can be added by adding 'dialout' group to the user. Additionally if Spice or VNC remote access is required, user will need to access /dev/dri/render128 which is allowed by group 'render' or 'video' if 'render' is not defined.

Additionally we need to add udev rules to set correct group (e.g. kvm, vfio, tun/tap devices).

File: /etc/udev/rules.d/10-kvm.rules
```
sudo cp ./udev/10-kvm.rules /etc/udev/rules.d/10-kvm.rules
```
File: /etc/udev/rules.d/80-tap-kvm-group.rules
```
sudo cp ./udev/10-kvm.rules  /etc/udev/rules.d/80-tap-kvm-group.rules
```
## Reboot
Then reboot.
```
sudo shutdown -r now
```

Let say user vmadmin is the designated user, below is the script:

```
su vmadmin 

TODO
#sudo usermod -a -G kvm $USER
#Throws error
#sudo usermod -a -G render $USER
#Throws error
sudo usermod -a -G video $USER
sudo usermod -a -G dialout $USER
```
Besides permission, the designated user should also be give unlimiter memory lock capability. The following lines can be added to /etc/security/limits.conf
```
vmadmin       hard    memlock         unlimited
vmadmin       soft    memlock         unlimited
```


## Verifying correct kernel and features are turned on.

Once the system comes back online, we should be able to verify if the kernel is properly loaded by checking /proc/cmdline
```
$ cat /proc/cmdline
BOOT_IMAGE=/boot/vmlinuz-5.4.54-intelgvt+ root=UUID=baea869f-283c-483eb29e-8ea87927b48c ro splash quiet i915.enable_gvt=1 i915.enable_fbc=0 kvm.ignore_msrs=1 intel_iommu=on,igfx_off drm.debug=0 vt.handoff=1
```

## Verifying if GVT-g is working

The following command will show if vfio-mdev is working on i915
```
$ ls -l /sys/bus/pci/devices/0000:00:02.0/mdev_supported_types/
total 0
drwxr-xr-x 6 root root 0 Feb 28 13:09 ./
drwxr-xr-x 14 root root 0 Feb 24 14:55 ../
drwxr-xr-x 3 root root 0 Feb 24 14:55 i915-GVTg_V5_1/
drwxr-xr-x 3 root root 0 Feb 24 14:55 i915-GVTg_V5_2/
drwxr-xr-x 3 root root 0 Feb 24 14:55 i915-GVTg_V5_4/
drwxr-xr-x 3 root root 0 Feb 24 14:55 i915-GVTg_V5_8/
```
For GVTg with direct display extension, there are several sysfs files added (gvt_disp_*).
```
$ ls /sys/class/drm/card0/
card0-DP-1      gt_act_freq_mhz    gt_RP1_freq_mhz       gvt_disp_ports_status
card0-DP-2      gt_boost_freq_mhz  gt_RPn_freq_mhz       metrics
card0-HDMI-A-1  gt_cur_freq_mhz    gvt_disp_auto_switch  power
dev             gt_max_freq_mhz    gvt_disp_edid_filter  subsystem
device          gt_min_freq_mhz    gvt_disp_ports_mask   uevent
error           gt_RP0_freq_mhz    gvt_disp_ports_owner
```
If the udev rules are correct, we should see those devices are setup with the right group.
```
$ls -l /dev/kvm
crw-rw---- 1 root kvm 10, 232 Apr 21 17:55 /dev/kvm
$ls -l /dev/tap*
crw-rw---- 1 root kvm 236, 1 Apr 21 17:55 /dev/tap3
```
