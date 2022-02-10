#!/bin/bash

#-------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. 
#--------------------------------------------------------------------------

VERSION="1.0.2"

usage() {
cat << EOT >&2
$(basename ${0}) v$VERSION

Usage: ${0} -i ETH_IFACE -f FE_PORT -a DEST_HOST -b DEST_PORT [-s <INTERVAL>] [-d]
       ${0} -h (print this help information)

Options:
  -i ETH_IFACE  forward packets arriving on this interface
  -f FE_PORT    forward packets arriving on this port
  -a DEST_HOST  destination host to forward packets to
  -b DEST_PORT  destination port to forward packets to
  -s INTERVAL   do not terminate, sleep and update the rules if destination host IP changed
  -r            remove rules (ignores -s)
EOT
}

info() {
	tput setaf 2
	echo $@
	tput sgr0
}

error() {
	tput setaf 1
	echo "ERROR: $@"
	tput sgr0
	echo "Try \`${0} -h\` for more information."
}

resolve() {
	if [[ ${DEST_HOST} =~ ^([0-9]{1,3}\.){3}[0-9]{3}$ ]]; then
		DEST_IP=${DEST_HOST}
	else
		host_out=$(host ${DEST_HOST})
		if [[ $? == 0 ]]; then
			DEST_IP=$(host ${DEST_HOST} | head -n 1 | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}")
		else
			error "Cannot resolve host \`$DEST_HOST', aborting"
			exit 1
		fi
	fi
}

install_rules() {
	dnat_rulespec="PREROUTING -p tcp -i ${ETH_IF} --dport ${FE_PORT} -j DNAT --to $1:${DEST_PORT}"
	snat_rulespec="POSTROUTING -o ${ETH_IF} -j MASQUERADE"
	#snat_rulespec="POSTROUTING -p tcp -o ${ETH_IF} --dport ${DEST_PORT} -j SNAT -d $1 --to-source ${LOCAL_IP}:${FE_PORT}"

	if iptables -t nat -C $dnat_rulespec >&/dev/null; then
		info "DNAT rule is already installed, skipping"
	else
		info "Installing DNAT rule ${LOCAL_IP}:${FE_PORT} -> $1:${DEST_PORT}"
		iptables -t nat -A $dnat_rulespec
	fi

	if iptables -t nat -C $snat_rulespec >&/dev/null; then
		info "SNAT rule is already installed, skipping"
	else
		info "Installing SNAT rule ${LOCAL_IP}:${FE_PORT} -> $1:${DEST_PORT}"
		iptables -t nat -A $snat_rulespec
	fi
}

remove_rules() {
	dnat_rulespec="PREROUTING -p tcp -i ${ETH_IF} --dport ${FE_PORT} -j DNAT --to $1:${DEST_PORT}"
	snat_rulespec="POSTROUTING -o ${ETH_IF} -j MASQUERADE"
	#snat_rulespec="POSTROUTING -p tcp -o ${ETH_IF} --dport ${DEST_PORT} -j SNAT -d $1 --to-source ${LOCAL_IP}:${FE_PORT}"

	if iptables -t nat -C $dnat_rulespec >&/dev/null; then
	info "-- Removing DNAT rule ${LOCAL_IP}:${FE_PORT} -> $1:${DEST_PORT}"
		iptables -t nat -D $dnat_rulespec
	else
		info "DNAT rule is not present, ignoring"
	fi

	if iptables -t nat -C $snat_rulespec >&/dev/null; then
	    info "-- Removing SNAT rule ${LOCAL_IP}:${FE_PORT} -> $1:${DEST_PORT}"
		iptables -t nat -D $snat_rulespec
	else
		info "SNAT rule is not present, ignoring"
	fi
}

# Make sure we're running as root
if [ -z ${UID} ]; then
	UID=$(id -u)
fi
if [ "${UID}" != "0" ]; then
	error "user must be root"
	exit 1
fi

if [[ $# -eq 0 ]]; then
	error "no options given"
	exit 1
fi
while getopts 'i:f:a:b:s:r' OPTS; do
	case "${OPTS}" in
		i)
			info "Using ethernet interface ${OPTARG}"
			ETH_IF=${OPTARG}
			;;
		f)
			info "Frontend port is ${OPTARG}"
			FE_PORT=${OPTARG}
			;;
		a)
			info "Destination host is ${OPTARG}"
			DEST_HOST=${OPTARG}
			resolve $DEST_HOST
			;;
		b)
			info "Destination port is ${OPTARG}"
			DEST_PORT=${OPTARG}
			;;
		s)
			info "Polling interval is ${OPTARG}"
			INTERVAL=${OPTARG}
			;;
		r)
			REMOVE_RULES=TRUE
			;;
		h)
			usage
			exit 0
			;;
		*)
			usage
			exit 1
			;;
	esac
done

if [ -z ${ETH_IF} ]; then
	error "ethernet interface not specified"
	exit 1
fi
	if [ -z ${FE_PORT} ]; then
	error "frontend port not specified"
	exit 1
fi
if [ -z ${DEST_HOST} ]; then
	error "destination host not specified"
	exit 1
fi
if [ -z ${DEST_PORT} ]; then
	error "destination port not specified"
	exit 1
fi

# Make sure IP Forwarding is enabled in the kernel
IP_FW_ENABLED=$(cat /proc/sys/net/ipv4/ip_forward)
if [[ $IP_FW_ENABLED != 1 ]]; then
	info "Enabling IP forwarding..."
	echo "1" > /proc/sys/net/ipv4/ip_forward
fi

# Get local IP
LOCAL_IP=$(ip addr ls ${ETH_IF} | grep -w inet | awk '{print $2}' | awk -F/ '{print $1}')
info "Using Local IP ${LOCAL_IP}"

# Do
if [[ $REMOVE_RULES ]]; then
	remove_rules $DEST_IP
else
	install_rules $DEST_IP
fi

# If an interval is given, loop and update iptables when the destination IP changes
while [ $INTERVAL ]; do
	sleep $INTERVAL
	OLD_DEST_IP=$DEST_IP
	resolve ${DEST_HOST}
	if [ $DEST_IP != $OLD_DEST_IP ]; then
		info "** Destination IP changed to $DEST_IP"
		remove_rules OLD_DEST_IP
		install_rules DEST_IP
	fi
done

