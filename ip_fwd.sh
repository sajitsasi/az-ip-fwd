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
	echo $(date +"%F %T") "$@"
}

fail() {
	echo $(date +"%F %T") ERROR: "$@"
	echo "Try \`${0} -h\` for more information."
	exit 1
}

resolve() {
	if [[ ${DEST_HOST} =~ ^([0-9]{1,3}\.){3}[0-9]{3}$ ]]; then
		DEST_IP=${DEST_HOST}
	else
		DEST_IP=$(getent hosts ${DEST_HOST} | cut -f1 -d' ')
		[[ "$?" != 0 ]] && fail "Cannot resolve host \`${DEST_HOST}', aborting"
	fi
}

install_rules() {
	dnat_rulespec="PREROUTING -p tcp -i ${ETH_IF} --dport ${FE_PORT} -j DNAT --to $1:${DEST_PORT}"
	snat_rulespec="POSTROUTING -o ${ETH_IF} -j MASQUERADE"
	#snat_rulespec="POSTROUTING -p tcp -o ${ETH_IF} --dport ${DEST_PORT} -j SNAT -d $1 --to-source ${LOCAL_IP}:${FE_PORT}"

	if iptables -t nat -C $dnat_rulespec >&/dev/null; then
		info "DNAT rule is already installed, skipping"
	else
		info "++ Installing DNAT rule ${LOCAL_IP}:${FE_PORT} -> $1:${DEST_PORT} (${ETH_IF})"
		iptables -t nat -A $dnat_rulespec
	fi

	if iptables -t nat -C $snat_rulespec >&/dev/null; then
		info "SNAT rule is already installed, skipping"
	else
		info "++ Installing SNAT rule ${LOCAL_IP}:${FE_PORT} -> $1:${DEST_PORT} (${ETH_IF})"
		iptables -t nat -A $snat_rulespec
	fi
}

remove_rules() {
	dnat_rulespec="PREROUTING -p tcp -i ${ETH_IF} --dport ${FE_PORT} -j DNAT --to $1:${DEST_PORT}"
	snat_rulespec="POSTROUTING -o ${ETH_IF} -j MASQUERADE"
	#snat_rulespec="POSTROUTING -p tcp -o ${ETH_IF} --dport ${DEST_PORT} -j SNAT -d $1 --to-source ${LOCAL_IP}:${FE_PORT}"

	if iptables -t nat -C $dnat_rulespec >&/dev/null; then
	info "-- Removing DNAT rule ${LOCAL_IP}:${FE_PORT} -> $1:${DEST_PORT} (${ETH_IF})"
		iptables -t nat -D $dnat_rulespec
	else
		info "DNAT rule is not present, ignoring"
	fi

	if iptables -t nat -C $snat_rulespec >&/dev/null; then
	    info "-- Removing SNAT rule ${LOCAL_IP}:${FE_PORT} -> $1:${DEST_PORT} (${ETH_IF})"
		iptables -t nat -D $snat_rulespec
	else
		info "SNAT rule is not present, ignoring"
	fi
}

# Make sure we're running as root
[ "$(id -u)" != "0" ] && fail "user must be root"

# Parse command line args
[[ $# -eq 0 ]] && fail "no options given"
while getopts 'i:f:a:b:s:rh' OPT; do
	case "${OPT}" in
		i) ETH_IF=${OPTARG} ;;
		f) FE_PORT=${OPTARG} ;;
		a) DEST_HOST=${OPTARG} ;;
		b) DEST_PORT=${OPTARG} ;;
		s) INTERVAL=${OPTARG} ;;
		r) REMOVE_RULES=yes ;;
		h) usage; exit 0 ;;
		*) error "Unrecognized option ${OPT}"; exit 1 ;;
	esac
done
[ -z ${ETH_IF} ] && fail "ethernet interface not specified"
[ -z ${FE_PORT} ] && fail "frontend port not specified"
[ -z ${DEST_HOST} ] && fail "destination host not specified"
[ -z ${DEST_PORT} ] && fail "destination port not specified"
if [ -n "${INTERVAL}" ]; then
	[[ "${INTERVAL}" =~ ^[0-9]+$ ]] || fail "interval should be an integer"
	[ "${INTERVAL}" == "0" ]        && fail "interval should be greater than 0"
fi
resolve ${DEST_HOST}
LOCAL_IP=$(ip addr ls ${ETH_IF}|grep -w inet|sed 's/.*inet \([0-9.]\+\).*/\1/')

# Make sure IP forwarding is enabled in the kernel
IP_FW_ENABLED=$(cat /proc/sys/net/ipv4/ip_forward)
if [[ ${IP_FW_ENABLED} != 1 ]]; then
	info "Enabling IP forwarding..."
	echo "1" > /proc/sys/net/ipv4/ip_forward
fi

if [ -n "${INTERVAL}" ]; then
	if [[ ${DEST_HOST} =~ '([0-9]{1,3}\.){3}[0-9]{1,3}' ]]; then
		info "${DEST_HOST} is an IP address. -s will be ignored."
		unset INTERVAL
	fi
fi

# Do the work.
if [ -n "${REMOVE_RULES}" ]; then
	remove_rules ${DEST_IP}
	exit 0
else
	install_rules ${DEST_IP}
fi
# If an interval wasn't given, we're done.
[ -z "${INTERVAL}" ] && exit 0

# If an interval is given, loop and update iptables when the destination IP changes
trap "remove_rules ${DEST_IP}; exit 0" SIGTERM SIGINT SIGHUP SIGQUIT
info "Will resolve '${DEST_HOST}' every ${INTERVAL} second(s)"
while [[ TRUE ]]; do
	sleep ${INTERVAL}
	OLD_DEST_IP=${DEST_IP}
	resolve ${DEST_HOST}
	if [ ${DEST_IP} != ${OLD_DEST_IP} ]; then
		info "** Destination IP changed to ${DEST_IP}"
		remove_rules ${OLD_DEST_IP}
		install_rules ${DEST_IP}
	fi
done
