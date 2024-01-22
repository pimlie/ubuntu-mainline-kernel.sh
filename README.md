# ubuntu-mainline-kernel.sh

Bash script for Ubuntu (and derivatives as LinuxMint) to easily (un)install kernels from the [Ubuntu Kernel PPA](https://kernel.ubuntu.com/~kernel-ppa/mainline/).

## Warnings

:warning: Use this script at your own risk. Be aware that the kernels installed by this script are [unsupported](https://wiki.ubuntu.com/Kernel/MainlineBuilds#Support_.28BEWARE:_there_is_none.29)

:unlock: Do not use this script if you don't have to or don't know what you are doing. You won't be [covered](https://github.com/pimlie/ubuntu-mainline-kernel.sh/issues/32) by any security guarantees. The intended purpose by Ubuntu for the mainline ppa kernels is for debugging issues.

:information_source: We strongly advise to keep the default Ubuntu kernel installed as there is no safeguard that at least one kernel is installed on your system.

## Install
```
apt install wget
wget https://raw.githubusercontent.com/pimlie/ubuntu-mainline-kernel.sh/master/ubuntu-mainline-kernel.sh
chmod +x ubuntu-mainline-kernel.sh
sudo mv ubuntu-mainline-kernel.sh /usr/local/bin/
```

If you want to automatically check for a new kernel version when you login:
```
wget https://raw.githubusercontent.com/pimlie/ubuntu-mainline-kernel.sh/master/UbuntuMainlineKernel.desktop
mv UbuntuMainlineKernel.desktop ~/.config/autostart/
```

## SecureBoot

> :warning: There is no support for creating and enrolling your own MOK. If you don't know how to do that then you could use the `mok-setup.sh` script from [berglh/ubuntu-sb-kernel-signing](https://github.com/berglh/ubuntu-sb-kernel-signing) to help you get started (at your own risk)

The script supports self signing the mainline kernels. Edit the script and set `sign_kernel=1` and
update the paths to your MOK key & certificate. (The default paths are the ones as created by the `mok-setup.sh` script from [berglh/ubuntu-sb-kernel-signing](https://github.com/berglh/ubuntu-sb-kernel-signing))

## Usage
```
Usage: ubuntu-mainline-kernel.sh -c|-l|-r|-u

Download & install the latest kernel available from kernel.ubuntu.com

Arguments:
  -c               Check if a newer kernel version is available
  -b [VERSION]     Build kernel VERSION locally and then install it (requires git & docker)
  -i [VERSION]     Install kernel VERSION, see -l for list. You don't have to prefix
                   with v. E.g. -i 4.9 is the same as -i v4.9. If version is
                   omitted the latest available version will be installed
  -l [SEARCH]      List locally installedkernel versions. If an argument to this
                   option is supplied it will search for that
  -r [SEARCH]      List available kernel versions. If an argument to this option
                   is supplied it will search for that
  -u [VERSION]     Uninstall the specified kernel version. If version is omitted,
                   a list of max 10 installed kernel versions is displayed
  --update         Update this script by redownloading it from github
  -h               Show this message

Optional:
  -p, --path DIR       The working directory, .deb files will be downloaded into
                       this folder. If omitted, the folder /tmp/ubuntu-mainline-kernel.sh/
                       is used. Path is relative from $PWD
  -ll, --low-latency   Use the low-latency version of the kernel, only for amd64 & i386
  -lpae, --lpae        Use the Large Physical Address Extension kernel, only for armhf
  --snapdragon         Use the Snapdragon kernel, only for arm64
  -do, --download-only Only download the deb files, do not install them
  -ns, --no-signature  Do not check the gpg signature of the checksums file
  -nc, --no-checksum   Do not check the sha checksums of the .deb files
  -d, --debug          Show debug information, all internal commands echo their output
  --rc                 Also include release candidates
  --yes                Assume yes on all questions (use with caution!)
```

> :information_source: Since ~v5.18 Ubuntu does not publish low-latency mainline kernels anymore, see this [AskUbuntu](https://askubuntu.com/questions/1397410/where-are-latest-mainline-low-latency-kernel-packages) for more info

## Elevated privileges

This script needs elevated privileges when installing or uninstalling kernels.

Either run this script with sudo or configure the path to sudo within the script to sudo automatically

## Building kernels locally *(EXPERIMENTAL)*

> :warning: YMMV, this is experimental support. Don't build kernel's if you don't know what you are doing

> :warning: If the build fails, please debug yourself and create a PR with fixes if needed. Also if you don't know how to debug the build failure, then you probably shouldn't be building your own kernels!

> :information_schema: There are no plans to add full fledged support for building kernels. This functionality might stay experimental for a long time

The mainline kernel ppa only supports the latest Ubuntu release. But newer Ubuntu releases could use newer library versions then the current LTS releases (f.e. both libssl or glibc version issues have existed in the past). Which means that you won't be able to (fully) install the newer kernel anymore.

When that happens you could try to build your own kernel releases by using the `--build VERSION` argument (f.e. `-b 6.7.0`).

Kernel building support is provided by [TuxInvader/focal-mainline-builder](https://github.com/TuxInvader/focal-mainline-builder) so requires:

- git & docker
- quite a bit of free disk space (~3GB to checkout the kernel source, maybe ~10GB or more during build)
- can take quite a while depending on how fast your computer is

## Example output

Install latest version:
```
 ~ $ sudo ubuntu-mainline-kernel.sh -i
Finding latest version available on kernel.ubuntu.com
Latest version is v4.9.0 but seems its already installed, continue? (y/N)
Will download 5 files from kernel.ubuntu.com:
CHECKSUMS
CHECKSUMS.gpg
linux-headers-4.9.0-040900-generic_4.9.0-040900.201612111631_amd64.deb
linux-headers-4.9.0-040900_4.9.0-040900.201612111631_all.deb
linux-image-4.9.0-040900-generic_4.9.0-040900.201612111631_amd64.deb
Signature of checksum file has been successfully verified
Checksums of deb files have been successfully verified with sha256sum
Installing 3 packages
[sudo] password for pimlie:
Cleaning up work folder
```
Uninstall a version from a list
```
 ~ $ sudo ubuntu-mainline-kernel.sh -u
Which kernel version do you wish to uninstall?
[0]: v4.8.6-040806
[1]: v4.8.8-040808
[2]: v4.9.0-040900
type the number between []: 0
Are you sure you wish to remove kernel version v4.8.6-040806? (y/N)
The following packages will be removed:
linux-headers-4.8.6-040806-generic:amd64 linux-headers-4.8.6-040806-generic:all linux-image-4.8.6-040806-generic:amd64
Are you really sure? (y/N)
[sudo] password for pimlie:
Kernel v4.8.6 successfully purged
```

## Dependencies

* bash
* gnucoreutils
* dpkg
* wget (since 2018-12-14 as kernel ppa is now https only)

## Optional dependencies

* libnotify-bin (to show notify bubble when new version is found)
* bsdmainutils (format output of -l, -r with column)
* gpg (to check the signature of the checksum file)
* sha1sum/sha256sum (to check the .deb checksums)
* sbsigntool (to sign kernel images for SecureBoot)
* sudo

## Known issues (with workarounds)
- GPG is unable to import the key behind a proxy: #74
