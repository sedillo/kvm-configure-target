# Setting up services

In order to have KVM guest OS properly running with GVTg GPU, we need to have several services in order:
* VGPU service
* Guest OS service

Both services requires configuration which will be defined in an executable script file called /var/vm/scripts/env.sh
```
#!/bin/bash
# Note: VGPU ports mask setting must be done before any VGPU is created
# VGPU to PORT assignment
# 1 -> PORT_A (can't be used because special eDP case: WIP to resolve)
# 2 -> PORT_B
# 3 -> PORT_C
# 4 -> PORT_D
MASK=0x0000000000000402

# BKM: To generate UUID, use uuid command.
# For ease of identification, replicate and replace the last number with VGPU index
VGPU1="f50aab10-7cc8-11e9-a94b-6b9d8245bfc1"
VGPU2="f50aab10-7cc8-11e9-a94b-6b9d8245bfc2"
VGPU3="f50aab10-7cc8-11e9-a94b-6b9d8245bfc3"
VGPU=" $VGPU1 $VGPU2 $VGPU3 "
VGPU_TYPE="i915-GVTg_V5_4"
BASEVGPU="/sys/bus/pci/devices/0000:00:02.0"
DIR="/var/vm"
```

## VGPU service

VGPU service is responsible for defining display mapping and creation of VGPU. There will be two scripts provided to support the execution of VGPU service, one for creation and one for destruction of VGPUs.

File (executable): /var/vm/scripts/create-vgpu.sh
```
#!/bin/bash
envconfig="/var/vm/scripts/env.sh"
if [[ $EUID -ne 0 ]]; then
        echo "This script must be run by superuser."
        exit 1
fi

if [ -f $envconfig ]; then
        source $envconfig
else
        echo "Could not find necessary environment setting."
        exit 1
fi
# Setting VGPU mask
/bin/sh -c "echo $MASK > /sys/class/drm/card0/gvt_disp_ports_mask"
# iterate through vgpu uuid and create uuid
for uuid in $VGPU
do
        /bin/sh -c "echo $uuid > ${BASEVGPU}/mdev_supported_types/${VGPU_TYPE}/create"
done
```

File (executable): /var/vm/scripts/destroy-vgpu.sh
```
#!/bin/bash
envconfig="/var/vm/scripts/env.sh"
if [[ $EUID -ne 0 ]]; then
        echo "This script must be run by superuser."
        exit 1
fi

if [ -f $envconfig ]; then
        source $envconfig
else
        echo "Could not find necessary environment setting."
        exit 1
fi
# iterate through vgpu uuid and create uuid
for uuid in $VGPU
do
        if [ -f "${BASEVGPU}/${uuid}/remove" ]; then
                /bin/sh -c "echo 1 > ${BASEVGPU}/${uuid}/remove"
        else
                echo "VGPU ${uuid} does not exist."
        fi
done
```

The VGPU service file itself is below:
File:/etc/systemd/system/vgpu.service
```
[Unit]
Description=Create GVTg VGPU
# This unit creates 3 virtual GPUs with the UUIDs below.
# It also set the port map mask to 0 which disables direct display pipe to port map.
ConditionPathExists=/sys/bus/pci/devices/0000:00:02.0/mdev_supported_types
ConditionPathExists=/var/vm/scripts/env.sh
[Service]
Type=oneshot
RemainAfterExit=true
EnvironmentFile=/var/vm/scripts/env.sh
ExecStart=/var/vm/scripts/create-vgpu.sh
ExecStop=/var/vm/scripts/destroy-vgpu.sh
[Install]
WantedBy=multi-user.target
```
Once the files are located in place with the right permission (i.e. executable), we can enable the VGPU service.
```
$ sudo systemctl enable vgpu.service
$ sudo systemctl start vgpu.service
```

## QEMU service

QEMU service is responsible for starting and stopping VM. It depends on two exectable scripts:
* /var/vm/scripts/start-vm.sh
* /var/vm/scripts/stop-vm.sh

Both scripts requires a name as parameters. This name refers to a configuration file stored at /var/vm/cfg/${name}.sh.
Additionally the file also read configuration from /var/vm/scripts/env.sh.

File (executable): /var/vm/scripts/start-vm.sh
```
#!/bin/bash
iskvm=$(groups | grep kvm | wc -l)
if [[ $iskvm -ne 1 ]] && [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root or user with kvm group" 
   exit 1
fi

envconfig="/var/vm/scripts/env.sh"
if [ -f $envconfig ]; then
        source $envconfig
else
        echo "Could not find necessary environment setting."
        exit 1
fi

# check current dir
#DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
# echo "Current script location: "$DIR
# check if it has argument passed
if [ $# -eq 0 ]
then
        echo "No argument supplied, please pass the name of the vmname specified by cfg/vmname.sh"
        exit 1
fi

# check if configuration exist
CFG="$DIR/cfg/${1}.sh"
#echo "VM configuration path is $CFG"
if [[ -x "$CFG" ]]
then
        source $CFG
else
        echo "VM configuration file is either not found or not executable"
        exit 1
fi

QEMU="/usr/local/bin/qemu-system-x86_64 -enable-kvm "
DEF_MEMORY=2048
DEF_CPU=2
DEF_MACHINE="pc"

QEMU_SCRIPT="$QEMU "
# memory configuration
if [ -z "$MEMORY" ]
then
        MEMORY=$DEF_MEMORY
fi
# core configuration
if [ -z "$CPU" ]
then
        CPU=$DEF_CPU
fi

# machine configuration
if [ -z "$MACHINE" ]
then
        MACHINE=$DEF_MACHINE
fi

QEMU_SCRIPT+=" -m $MEMORY -smp $CPU -M $MACHINE"

if [ ! -z "$NAME" ]
then
        QEMU_SCRIPT+=" -name "$NAME
fi

#BIOS
if [ ! -z "$BIOS" ]
then
        QEMU_SCRIPT+=" -bios "$BIOS
fi


if [ ! -z "$HDD" ]
then
        QEMU_SCRIPT+=" -hda "$HDD
fi

if [ ! -z "$ISO" ]
then
        QEMU_SCRIPT+=" -cdrom "$ISO
fi

if [ -z "$MAC" ]
then
        QEMU_SCRIPT+=" -net nic "
else
        QEMU_SCRIPT+=" -net nic,model=virtio,macaddr="$MAC 
fi


if [ -z "$IFUP" ]
then
        QEMU_SCRIPT+=" -net user"
else
        QEMU_SCRIPT+=" -net tap,script="$IFUP",downscript=no"
fi


if [ ! -z "$VGA" ]
then
        QEMU_SCRIPT+=" -vga "$VGA
fi

if [ ! -z "$EGL" ]
then
        QEMU_SCRIPT+=" -display "$EGL
fi

QEMU_SCRIPT+=" -k en-us"

if [ ! -z "$SERIAL" ]
then
        QEMU_SCRIPT+=" -serial "$SERIAL
fi

if [ ! -z "$VNC" ]
then
        QEMU_SCRIPT+=" -vnc "$VNC
fi

if [ ! -z "$SPICE" ]
then
        QEMU_SCRIPT+=" -spice "$SPICE
fi

QEMU_SCRIPT+=" -machine kernel_irqchip=on "
if [ "$MACHINE" == "q35" ]
then
 	QEMU_SCRIPT+=" -global ICH9-LPC.disable_s3=1 -global ICH9-LPC.disable_s4=1 "
else
 	QEMU_SCRIPT+=" -global PIIX4_PM.disable_s3=1 -global PIIX4_PM.disable_s4=1 "
fi
QEMU_SCRIPT+=" -cpu host -usb -device usb-tablet "
if [ ! -z "$VGPU" ]
then
        if [ -z "$DISPLAY" ]
        then
                DISPLAY="off"
        fi
        QEMU_SCRIPT+=" -device vfio-pci,sysfsdev=/sys/bus/pci/devices/0000:00:02.0/$VGPU,rombar=0,display=$DISPLAY,x-igd-opregion=on"
fi

if [ ! -z "$DEVPT" ]
then
        QEMU_SCRIPT+=" $DEVPT"
fi

if [ ! -z "$MONITOR" ]
then
	QEMU_SCRIPT+=" -monitor telnet:localhost:$MONITOR,server,nowait,nodelay "
fi
# Daemonize and store PID at /tmp/qemu_filename.pid

QEMU_SCRIPT+=" -daemonize -pidfile /tmp/qemu_${1}.pid "
#echo "Script: "$QEMU_SCRIPT
#Run qemu
$QEMU_SCRIPT
```

File (executable): /var/vm/scripts/stop-vm.sh
```
#!/bin/bash
iskvm=$(groups | grep kvm | wc -l)
if [[ $iskvm -ne 1 ]] && [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root or user with kvm group" 
   exit 1
fi

envconfig="/var/vm/scripts/env.sh"
if [ -f $envconfig ]; then
        source $envconfig
else
        echo "Could not find necessary environment setting."
        exit 1
fi

# check current dir
#DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
# echo "Current script location: "$DIR
# check if it has argument passed
if [ $# -eq 0 ]
then
        echo "No argument supplied, please pass the name of the vmname specified by cfg/vmname.sh"
        exit 1
fi

# check if configuration exist
CFG="$DIR/cfg/${1}.sh"
#echo "VM configuration path is $CFG"
if [[ -x "$CFG" ]]
then
        source $CFG
else
        echo "VM configuration file is either not found or not executable"
        exit 1
fi

if [ ! -z "$MONITOR" ]
then
	echo 'system_powerdown' |  /usr/bin/nc localhost $MONITOR	
fi	
```

Below is an example of a configuration fiole for a VM:
File (executable): /var/vm/cfg/ubuntu.sh
```
#!/bin/sh
NAME="Ubuntu-Guest"
VGPU="f50aab10-7cc8-11e9-a94b-6b9d8245bfc2"
MAC="00:DE:AD:BE:EF:F1"
MACHINE="q35"
HDD=/home/vproadmin/vm/disk/ubuntu.qcow2
#ISO=/home/vproadmin/vm/iso/ubuntu.iso
BIOS=/home/vproadmin/vm/fw/OVMF.fd
#IFUP=/home/vproadmin/vm/script/qemu-ifup-bridge
DISPLAY="on"
VGA="none"
#SERIAL="stdio"
VNC=":1"
EGL="egl-headless"
MONITOR=7110
DEVPT="-device usb-host,hostbus=1,hostport=3.1 -device usb-host,hostbus=1,hostport=3.2"
```

In order to use those scripts and configuration to manage VM in an automated fashion, the following qemu@.service file should be defined to dynamically run the VM based on the configuration.

File: /etc/systemd/system/qemu@.service
```
[Unit]
Description=Auto start QEMU virtual machine
After=vgpu.service
[Service]
Type=forking
User=vmadmin
Group=kvm
LimitMEMLOCK=infinity:infinity
PIDFile=/tmp/qemu_%i.pid
ExecStart=/bin/sh -c "/var/vm/scripts/start-vm.sh %i"
ExecStop=/bin/sh -c "/var/vm/scripts/stop-vm.sh %i"
TimeoutStopSec=30
Restart=on-failure
RestartSec=60s
[Install]
WantedBy=multi-user.target
```
Note: edit the "User" to the designated user to run VM.

To ensure the service file is re-read by systemd, please call daemon-reload.
```
$ sudo systemctl daemon-reload
```
Let say we want to enable and to start Ubuntu VM automatically. Here is the step we need to do after we place the configuration file in /var/vm/cfg/:
```
$ sudo systemctl enable qemu@ubuntu.service
$ sudo systemctl start qemu@ubuntu.service
```
