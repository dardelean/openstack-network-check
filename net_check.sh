#!/bin/bash

set -e

# OVS file in which bridge_mapping are found

# In older OpenStack releases the OVS configurations were in the ml2.conf file
# in the newer releases there is a separate ovs agent file.
OVS_FILE="/etc/neutron/plugins/ml2/openvswitch_agent.ini"
if [ ! -f $OVS_FILE ]; then
        OVS_FILE="/etc/neutron/plugins/ml2/ml2_conf.ini"
fi

# First we check in the OVS file if there is a OVS bridge mapping for the neutron network
function check_net_bridge_mapping() {
        local PHYS_NET=$1
        MAPPINGS=`openstack-config --get $OVS_FILE ovs bridge_mappings`

        for MAP in $(echo $MAPPINGS | tr ',' ' ')
        do
                PHY_MAP=`echo $MAP | awk -F ":" '{print $1}'`
                if [ "$PHY_MAP" == "$PHYS_NET" ]; then
                        BRIDGE=`echo $MAP | awk -F ":" '{print $2}'`
                        echo "INFO: network $PHYS_NET has $BRIDGE bridge mapping"
                        return 0
                        break
                fi
        done

        if [ -z "$BRIDGE" ]; then
                echo "WARNING: $PHYS_NET network does not have a bridge mapping"
                return 1
        fi
}

# In the second pleace we check if the OVS bridge has a port for a network interface
function check_bridge_interface_mapping () {
        local BRIDGE=$1

        BRIDGE_PORTS=`ovs-vsctl list-ports $BRIDGE`
        for PORT in $BRIDGE_PORTS; do
                INTERFACE=`ip -o link show | awk -F': ' '{print $2}' | grep -F -x $PORT`
                if [ -z "$INTERFACE" ]; then
                        echo "WARNING: bridge $BRIDGE has no asociated NIC to it"
                        return 1
                else
                        echo "INFO: bridge $BRIDGE has a port in interface $INTERFACE"
                        return 0
                        break
                fi
        done
}

function usage() {
	echo -e "usage: $0 options\n"
	echo -e "This script checks if OpenStack networking is correctly configured, it may require openstack-config package\n"
	echo "OPTIONS:"
	echo "-h		Show this message"
	echo "-n <network ID>	Specify network to check"
	echo -e "-a		Check all available networks in Neutron\n"

	exit 0
}

[ $# -eq 0 ] && usage

while getopts "hn:a" OPTION; do
	case $OPTION in
		n) #get specific network
			NETWORKS=$OPTARG
			;;
		a) #get all networks
			NETWORKS=`neutron net-list | sed -e '1,3d;$d' | awk '{print $2}'`
			;;
		h | *) #show usage
			usage
			;;
	esac
done

for NETWORK in $NETWORKS; do
        NETWORK_NAME=`neutron net-show $NETWORK | awk '$2 == "name" {print $4}'`
        echo "=====================" "$NETWORK_NAME" "==================================="
        # Get physical network
        PHY_NETWORK=`neutron net-show $NETWORK_NAME | awk '$2 == "provider:physical_network" {print $4}'`

        if check_net_bridge_mapping $PHY_NETWORK && check_bridge_interface_mapping $BRIDGE; then
		echo "Everything looks OK for $NETWORK network!"
	else
		echo "Something went wrong!"
	fi

done

echo "========================================================================"
