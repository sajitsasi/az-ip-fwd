#!/bin/bash

#-------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. 
#--------------------------------------------------------------------------

usage() {
	echo -e "\e[33m"
	echo "usage: ${0} [-i <eth_interface>] [-f <frontend_port>] [-a <dest_host>] [-b <dest_port>] [-s <interval>]" 1>&2
	echo "where:" 1>&2
	echo "<eth_interface>: Interface on which packet will arrive and be forwarded" 1>&2
	echo "<frontend_port>: Frontend port on which packet arrives" 1>&2
	echo "<dest_host> : Destination to which the packet is forwarded" 1>&2
	echo "<dest_port> : Destination port to which packet is forwarded" 1>&2
	echo "<interval> : Do not terminate. Sleep this many seconds before updating the rules"
	echo -e "\e[0m"
}

resolve() {
	host ${DEST_HOST} | grep "has address" | awk '{print $NF}'
}

update_iptables() {
	# Do DNAT
	echo -e "\e[32mUpdating ($1) DNAT rule from ${LOCAL_IP}:${FE_PORT} to ${DEST_IP}:${DEST_PORT}...\e[0m"
	iptables -t nat $1 PREROUTING -p tcp -i ${ETH_IF} --dport ${FE_PORT} -j DNAT --to ${DEST_IP}:${DEST_PORT}

	# Do SNAT
	echo -e "\e[32mUpdating ($1) SNAT rule from ${DEST_IP}:${DEST_PORT} to ${LOCAL_IP}:${FE_PORT}...\e[0m"
	#iptables -t nat $1 POSTROUTING -p tcp -o ${ETH_IF} --dport ${DEST_PORT} -j SNAT -d ${DEST_IP} --to-source ${LOCAL_IP}:${FE_PORT}
	iptables -t nat $1 POSTROUTING -o ${ETH_IF} -j MASQUERADE
}

if [[ $# -eq 0 ]]; then
	echo -e "\e[31mERROR: no options given\e[0m"
	usage
	exit 1
fi
while getopts 'i:f:a:b:s:' OPTS; do
	case "${OPTS}" in
		i)
			echo -e "\e[32mUsing ethernet interface ${OPTARG}\e[0m"
			ETH_IF=${OPTARG}
			;;
		f)
			echo -e "\e[32mFrontend port is ${OPTARG}\e[0m"
			FE_PORT=${OPTARG}
			;;
		a)
			echo -e "\e[32mDestination IP Address is ${OPTARG}\e[0m"
			DEST_HOST=${OPTARG}
			;;
		b)
			echo -e "\e[32mDestination Port is ${OPTARG}\e[0m"
			DEST_PORT=${OPTARG}
			;;
		s)
			echo -e "\e[32mPolling interval is ${OPTARG}\e[0m"
			INTERVAL=${OPTARG}
			;;
		*)
			usage
			exit 1
			;;
	esac
done

if [ -z ${ETH_IF} ]; then
	echo -e "\e[31mERROR: ethernet interface not specified!!!\e[0m"
	usage
	exit 1
fi
	if [ -z ${FE_PORT} ]; then
	echo -e "\e[31mERROR: frontend port not specified!!!\e[0m"
	usage
	exit 1
fi
if [ -z ${DEST_HOST} ]; then
	echo -e "\e[31mERROR: destination IP not specified!!!\e[0m"
	usage
	exit 1
fi
if [ -z ${DEST_PORT} ]; then
	echo -e "\e[31mERROR: destination port not specified!!!\e[0m"
	usage
	exit 1
fi

#1. Make sure you're root
echo -e "\e[32mChecking whether we're root...\e[0m"
if [ -z ${UID} ]; then
	UID=$(id -u)
fi
if [ "${UID}" != "0" ]; then
	echo -e "\e[31mERROR: user must be root\e[0m"
	exit 1
fi

# Make sure IP Forwarding is enabled in the kernel
echo -e "\e[32mEnabling IP forwarding...\e[0m"
echo "1" > /proc/sys/net/ipv4/ip_forward

# Check if IP or hostname is specified for destination IP
if [[ ${DEST_HOST} =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	DEST_IP=${DEST_HOST}
else
	DEST_IP=$(resolve ${DEST_HOST})
fi
echo -e "\e[32mUsing Destination IP ${DEST_IP}\e[0m"

# Get local IP
LOCAL_IP=$(ip addr ls ${ETH_IF} | grep -w inet | awk '{print $2}' | awk -F/ '{print $1}')
echo -e "\e[32mUsing Local IP ${LOCAL_IP}\e[0m"

# Run one update
update_iptables -A

# If an interval is given, loop and update iptables when the destination IP changes
while [ $INTERVAL ]; do
	sleep $INTERVAL
	NEW_DEST_IP=$(resolve ${DEST_HOST})
	if [ $NEW_DEST_IP != $DEST_IP ]; then
		update_iptables -D
		DEST_IP=$NEW_DEST_IP
		update_iptables -A
	fi
done

# This only runs if an interval wasn't given
echo -e "\e[32mDone!\e[0m"
