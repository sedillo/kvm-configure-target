# Base system preparation
Base system preparation involves:
* Hardware preparation/UEFI Settings
* Kernel compilation, installation and settings modification

## Hardware preparation/UEFI settings

Key area to configure to ensure maximum utilization of hardware are:
- VT-d setting: enabled
- Graphic Aperture size: 1024MB

## Kernel compilation

Kernel compilation requires many development tools (compiler, linker and supporting libraries) to be available on the system. For consistency and repeatability, it is recommended to contain this process within an environment. In order to achieve this, we could leverage Docker container.
The following [Dockerfile](../dockerfile/Dockerfile) describes the build script for such container (Ubuntu 20.04).

```
FROM ubuntu:focal
MAINTAINER Joko Sastriawan
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get -y upgrade \
 && apt-get -y install tzdata \
 && apt-get -y install build-essential \
	git devscripts libfdt-dev libpixman-1-dev libssl-dev \
	bison flex kernel-package vim socat libsdl1.2-dev libsdl2-dev \ 
	libspice-server-dev autoconf libtool \
	python-dev liblzma-dev libc6-dev libegl1-mesa-dev \
	libepoxy-dev libdrm-dev libgbm-dev \
	libegl1-mesa-dev libgtk2.0-dev libusb-1.0.0-dev \
	device-tree-compiler texinfo python3-sphinx libaio-dev \ 
	libattr1-dev libbrlapi-dev libcap-dev libcap-ng-dev \ 
	libcurl4-gnutls-dev gnutls-dev libgtk-3-dev libvte-2.91-dev \
	libiscsi-dev libncursesw5-dev libvirglrenderer-dev \
	libnuma-dev librados-dev librbd-dev libsasl2-dev \
	libseccomp-dev librdmacm-dev libibverbs-dev libibumad-dev \
 	libusbredirparser-dev libssh-dev libxen-dev nettle-dev \
	uuid-dev xfslibs-dev libjpeg-dev libpmem-dev \
	gcc-s390x-linux-gnu gcc-alpha-linux-gnu \
	libc6.1-dev-alpha-cross gcc-powerpc64-linux-gnu rsync libelf-dev \
	wget liblz4-tool \
 && apt-get clean

```
Assuming proper docker environment is setup, the container image could be build using the following command:
```
$ cd dockerfile
$ docker build . -t mydocker/kernelbuilder
```
If the process is successfully completed, container image mydocker/kernelbuilder should be registered on local Docker environment.

This [build.sh](../build/build.sh) script will download Linux kernel at specified repository url and specific branch and place it in folder named 'kernel'. 

```
#!/bin/bash
# Variables
repo="https://github.com/intel/linux-intel-lts.git"
branch="5.4/yocto"
patchesfolder=""
configurl="https://kernel.ubuntu.com/~kernel-ppa/config/focal/linux/5.4.0-44.48/amd64-config.flavour.generic"
version="-intelgvt"
revision="3.0"

# git shallow clone linux kernel at specified branch with single history depth
echo "Performing shallow clone of kernel"
git clone --depth 1 $repo --branch $branch --single-branch kernel


# Apply all patches from folder specified by patchesfolder to git repo at folder named kernel
if [ ! -z "$patchesfolder" ] && [ -d "$patchesfolder" ]; then
    echo "Apply kernel patches"
    git apply --directory=kernel $patchesfolder/*
fi

# Fetch kernel config to .config and apply it using make oldconfig
if [ ! -z "$configurl" ]; then
    echo "fetching kernel config from $configurl"
    /usr/bin/wget -q -O kernel/.config $configurl
fi

echo "Apply kernel config"
( cd kernel && yes '' | make oldconfig )

# Run kernel package building using Ubuntu kernel packaging convention, \
# this will take a long time
echo "Build kernel_image and kernel_headers"
( cd kernel && CONCURRENCY_LEVEL=`nproc` fakeroot make-kpkg --initrd --append-to-version=$version \
        --revision $revision --overlay-dir=/usr/share/kernel-package kernel_image kernel_headers )

```
The following command sequence will create a temporary space to build the kernel using the container environment.
```
$ cd /home/user
$ mkdir buildfolder
$ cp $path_to_script/build.sh buildfolder
$ chmod a+x buildfolder/build.sh
$ docker run -it -v /home/user/buildfolder:/build --name bob mydocker/kernelbuilder
```
Then you should be in docker environment:
```
# cd /build
# ./build.sh
```
After few minutes depending on your CPU power, you should have linux-image and linux-headers Debian package insode /home/user/buildfolder.
