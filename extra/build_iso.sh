#!/bin/bash

## Remaster TCL for the Discovery Image
# (from http://wiki.tinycorelinux.net/wiki:remastering)
#
# This script will build the boot image. You will need squashfs-tools and 
# advancecomp. Run it as root, or with passwordless sudo, or the password prompts
# may get lost when the rake task is run.

# Setup
GEMS="facter json_pure rack rack-protection tilt sinatra"
TGZS="libssl-0.9.8 ruby"

TOPDIR=`mktemp -d`
cd $TOPDIR

# Download/Unpack TCL ISO
wget http://distro.ibiblio.org/tinycorelinux/4.x/x86/release/Core-current.iso -O tcl.iso
mkdir loop && mount -oloop tcl.iso loop/
cp loop/boot/core.gz loop/boot/vmlinuz .
umount loop && rmdir loop

# Modify basic image:
mkdir extract && cd extract
zcat $TOPDIR/core.gz | sudo cpio -i -H newc -d
mkdir opt/gems && cd opt/gems
for n in $GEMS ; do gem fetch $n ; done

# Build the init script
echo "" >> ../bootlocal.sh
for n in $GEMS ; do echo "gem install -l /opt/gems/`ls *$n-[0-9]*.gem`" >> ../bootlocal.sh ; done
echo "" >> ../bootlocal.sh
echo "/usr/share/foreman-proxy/bin/smart-proxy" >> ../bootlocal.sh
echo "/usr/share/foreman-proxy/bin/discover_host" >> ../bootlocal.sh

# Repack
cd $TOPDIR/extract
find | cpio -o -H newc | gzip -2 > $TOPDIR/tinycore.gz
cd $TOPDIR && advdef -z4 tinycore.gz
rm -rf $TOPDIR/extract
IMAGES="tinycore.gz "

# Convert TGZs to GZs
for url in $TGZS ; do
  wget http://repo.tinycorelinux.net/4.x/x86/tcz/$url.tcz
  unsquashfs $url.tcz && cd squashfs-root
  find | cpio -o -H newc | gzip -2 > ../$url.gz
  cd .. && advdef -z4 $url.gz
  rm -rf squashfs-root
  IMAGES="$IMAGES $url.gz "
done

# Build Rubygems:
wget http://production.cf.rubygems.org/rubygems/rubygems-1.8.24.tgz
mkdir tmp-install-rubygems && cd tmp-install-rubygems
mkdir rubygems
tar xvzf ../rubygems-1.8.24.tgz && cd rubygems-1.8.24
ruby setup.rb --destdir=../rubygems --prefix=/usr/local
cd ../rubygems
sed -i 's?#!.*?#!/usr/local/bin/ruby?' ./usr/local/bin/gem
mkdir ./usr/local/lib/ruby/1.8 -p
mv ./usr/local/lib/* ./usr/local/lib/ruby/1.8
chown -R 0:0 .
find | cpio -o -H newc | gzip -2 > $TOPDIR/rubygems.gz
cd $TOPDIR && advdef -z4 rubygems.gz
rm -rf tmp-install-rubygems rubygems-1.8.24.tgz
IMAGES="$IMAGES rubygems.gz "

# Proxy.gz
mkdir -p ./proxy/usr/share
mkdir -p ./proxy/var/run/foreman-proxy
mkdir -p ./proxy/var/log/foreman-proxy
git clone https://github.com/theforeman/smart-proxy.git ./proxy/usr/share/foreman-proxy
wget https://raw.github.com/GregSutcliffe/foreman_discovery/master/extra/discover_host -O ./proxy/usr/share/foreman-proxy/bin/discover_host
chmod 755 ./proxy/usr/share/foreman-proxy/bin/discover_host
cp ./proxy/usr/share/foreman-proxy/config/settings.yml{.example,}
sed -i 's/.*:bmc:.*/:bmc: true/' ./proxy/usr/share/foreman-proxy/config/settings.yml
sed -i 's/.*:bmc_default_provider:.*/:bmc_default_provider: shell/' ./proxy/usr/share/foreman-proxy/config/settings.yml
#Shell interface calls shutdown which doesn't exist in TCL
mkdir -p ./proxy/sbin
echo -e "#\x21/bin/sh\nexec /sbin/reboot" > ./proxy/sbin/shutdown
chmod 755 ./proxy/sbin/shutdown
cd proxy
find | cpio -o -H newc | gzip -2 > ../proxy.gz
cd $TOPDIR && advdef -z4 proxy.gz
rm -rf proxy
IMAGES="$IMAGES proxy.gz"

# Use Gz chaining:
cat $IMAGES > initrd.gz
chmod 755 $TOPDIR
echo "#TMPDIR# $TOPDIR"