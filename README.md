ubuntu-mainline-kernel.sh
=================

Bash script for Ubuntu (and derivatives as LinuxMint) to easily (un)install kernels from the [Ubuntu Kernel PPA](http://kernel.ubuntu.com/~kernel-ppa/mainline/).

Install
----------------
```
wget https://raw.githubusercontent.com/pimlie/ubuntu-mainline-kernel.sh/master/ubuntu-mainline-kernel.sh
chmod +x ubuntu-mainline-kernel.sh
sudo mv ubuntu-mainline-kernel.sh /usr/local/bin/
```

If you want to automatically check for a new kernel version when you login:
```
wget https://raw.githubusercontent.com/pimlie/ubuntu-mainline-kernel.sh/master/UbuntuMainlineKernel.desktop
mv UbuntuMainlineKernel.desktop ~/.config/autostart/
```

Usage
-----------------
```
Usage: ./ubuntu-mainline-kernel.sh -c|-l|-r|-u

Download & install the latest kernel available from kernel.ubuntu.com

Arguments:
  -c               Check if a newer kernel version is available
  -i [VERSION]     Install kernel VERSION, see -l for list. You dont have to prefix
                   with v. E.g. -i 4.9 is the same as -i v4.9. If version is
                   omitted the latest available version will be installed
  -l [SEARCH]      List locally installedkernel versions. If an argument to this
                   option is supplied it will search for that
  -r [SEARCH]      List available kernel versions. If an argument to this option
                   is supplied it will search for that
  -u [VERSION]     Uninstall the specified kernel version. If version is omitted,
                   a list of max 10 installed kernel versions is displayed
  -h               Show this message

Optional:
  -p, --path DIR       The working directory, .deb files will be downloaded into 
                       this folder. If omitted, the folder /tmp/ubuntu-mainline-kernel.sh/ 
                       is used. Path is relative from $PWD
  -ll, --low-latency   Use the low-latency version of the kernel, only for amd64 & i386
  -lpae, --lpae        Use the Large Physical Address Extension kernel, only for armhf
  -do, --download-only Only download the deb files, do not install them
  -ns, --no-signature  Do not check the gpg signature of the checksums file
  -nc, --no-checksum   Do not check the sha checksums of the .deb files
  -d, --debug          Show debug information, all internal command's echo their output
  --yes                Assume yes on all questions (use with caution!)
```

Example output
-------------------

Install latest version:
```
 ~ $ ./kernel-mainline-ppa.sh -i
Finding latest version available on kernel.ubuntu.com
Latest version is v4.9.0 but seems its already installed, continue? (y/N) 
Will download 5 files from kernel.ubuntu.com:
CHECKSUMS 
CHECKSUMS.gpg 
linux-headers-4.9.0-040900-generic_4.9.0-040900.201612111631_amd64.deb 
linux-headers-4.9.0-040900_4.9.0-040900.201612111631_all.deb 
linux-image-4.9.0-040900-generic_4.9.0-040900.201612111631_amd64.deb 
Signature of checksum file has been succesfully verified
Checksums of deb files have been succesfully verified with sha256sum
Installing 3 packages
[sudo] password for pimlie: 
Cleaning up work folder
```
Uninstall a version from a list
```
 ~ $ ./ubuntu-mainline-kernel.sh -u
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
Kernel v4.8.6 succesfully purged
```

Dependencies
----------------
* bash
* gnucoreutils
* dpkg

Optional dependencies
----------------
* bsdmainutils (format output of -l, -r with column)
* gpg (to check the signature of the checksum file)
* sha1sum/sha256sum (to check the .deb checksums)
* sudo

TODO
-----------------
- [] Support daily kernel builds
- [] Filter release canditates


