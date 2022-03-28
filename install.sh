#!/bin/sh
umask 022

# Make sure we're running as root
if [ "$(id -u)" != "0" ]; then
	echo "This script must be run as root." 1>&2
	exit 1
fi

cp ./ip_fwd.sh /usr/local/sbin
cp systemd/system/ip_fwd.service /etc/systemd/system

systemctl enable ip_fwd
systemctl start ip_fwd
