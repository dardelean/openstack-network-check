#!/bin/bash

set -e

# OVS file in which bridge_mapping are found
OVS_FILE="/etc/neutron/plugins/ml2/openvswitch_agent.ini"

# First we check in the OVS file if there is a OVS bridge mapping for the neutron network
function check_net_bridge_mapping(){
        local PHYS_NET=$1
        MAPPINGS=`grep 'bridge_mappings' $OVS_FILE | grep -v '#'`

        for MAP in $(echo $MAPPINGS | cut -d= -f2- | tr ',' ' ')
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
function check_bridge_interface_mapping (){
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

if [ -n "$1" ]; then
	if [[ "$1" == "-h" || "$1" == "--help" ]] ; then
		echo "Optional usage: `basename $0` [network ID]"
		exit 0
	else
        	NETWORKS="$1"
	fi
else
        NETWORKS=`neutron net-list | awk 'FNR>3 ' | awk 'FNR<3' | awk '{print $2}'`
fi



for NETWORK in $NETWORKS; do
        NETWORK_NAME=`neutron net-show $NETWORK | grep name | awk '{print $4}'`
        echo "=====================" "$NETWORK_NAME" "==================================="
        # Get physical network
        PHY_NETWORK=`neutron net-show $NETWORK_NAME | grep provider:physical_network | awk '{print $4}'`

        if check_net_bridge_mapping $PHY_NETWORK && check_bridge_interface_mapping $BRIDGE; then
		echo "Everything looks OK for $NETWORK network!"
	else
		echo "Something went wrong!"
	fi

done


echo "========================================================================"
