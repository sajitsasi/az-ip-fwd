#!/bin/bash

#-------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.
#--------------------------------------------------------------------------

usage() {
        echo -e "\e[33m"
        echo "usage: ${0} [-i <eth_interface>] [-f <frontend_port>] [-a <dest_ip_addr>] [-b <dest_port>]" 1>&2
        echo "where:" 1>&2
        echo "<eth_interface>: Interface on which packet will arrive and be forwarded" 1>&2
        echo "<frontend_port>: Frontend port on which packet arrives" 1>&2
        echo "<dest_port>    : Destination port to which packet is forwarded" 1>&2
        echo "<dest_ip_addr> : Destination IP which packet is forwarded" 1>&2
        echo -e "\e[0m"
}

if [[ $# -eq 0 ]]; then
        echo -e "\e[31mERROR: no options given\e[0m"
        usage
        exit 1
fi
while getopts 'i:f:a:b:' OPTS; do
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

#2. Make sure IP Forwarding is enabled in the kernel
echo -e "\e[32mEnabling IP forwarding...\e[0m"
echo "1" > /proc/sys/net/ipv4/ip_forward
# To make this changes presistance across the reboot.
#sed -i '/net.ipv4.ip_forward=1/s/^#//g' /etc/sysctl.conf

# Get the line number of the matching word
line_number=$(grep -n "net.ipv4.ip_forward=1" /etc/sysctl.d/99-sysctl.conf | cut -d ":" -f 1)

# Check if the line number was found
if [ -z "$line_number" ]; then
  echo "Error: matching word not found in file"
  exit 1
fi

# Backup the original file
cp /etc/sysctl.d/99-sysctl.conf /etc/sysctl.d/99-sysctl.conf.bak

# Uncomment the line
sed -i "${line_number}s/^#//" /etc/sysctl.d/99-sysctl.conf

# Verify if the line is uncommented
if grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.d/99-sysctl.conf; then
    echo "Line Uncommented Successfully"
else
    echo "Line Not Uncommented"
fi


#3. Check if IP or hostname is specified for destination IP
if [[ ${DEST_HOST} =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        DEST_IP=${DEST_HOST}
else
        DEST_IP=$(host ${DEST_HOST} | grep "has address" | awk '{print $NF}')
fi
echo -e "\e[32mUsing Destination IP ${DEST_IP}\e[0m"

#4. Get local IP
LOCAL_IP=$(ip addr ls ${ETH_IF} | grep -w inet | awk '{print $2}' | awk -F/ '{print $1}')
echo -e "\e[32mUsing Local IP ${LOCAL_IP}\e[0m"

#4. Do DNAT
echo -e "\e[32mCreating DNAT rule from ${LOCAL_IP}:${FE_PORT} to ${DEST_IP}:${DEST_PORT}...\e[0m"
iptables -t nat -A PREROUTING -p tcp -i ${ETH_IF} --dport ${FE_PORT} -j DNAT --to ${DEST_IP}:${DEST_PORT}

#4. Do SNAT
echo -e "\e[32mCreating SNAT rule from ${DEST_IP}:${DEST_PORT} to ${LOCAL_IP}:${FE_PORT}...\e[0m"
#iptables -t nat -A POSTROUTING -p tcp -o ${ETH_IF} --dport ${DEST_PORT} -j SNAT -d ${DEST_IP} --to-source ${LOCAL_IP}:${FE_PORT}
iptables -t nat -A POSTROUTING -o ${ETH_IF} -j MASQUERADE
echo -e "\e[32mDone!\e[0m"

