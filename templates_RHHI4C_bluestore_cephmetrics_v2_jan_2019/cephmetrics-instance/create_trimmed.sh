#!/usr/bin/env bash
# https://docs.openstack.org/networking-ovn/latest/install/tripleo.html
if [ -z "$1" ];
then
    echo "Usage: $0 conf_file" >&2
    exit 1
fi
set -ex

. $1
ADMIN_RC="$HOME/overcloudrc"
. $ADMIN_RC
PROVIDER_NET_ID=$(openstack network show $PROVIDER_NET_NAME -c id -f value)
PROVIDER_PORT_ID=$(openstack port list --network $PROVIDER_NET_ID --tags $PROVIDER_PORT_NAME -c id -f value)

PRIV_NET_ID=$(openstack network show $PRIV_NET_NAME -c id -f value)
PRIV_PORT_ID=$(openstack port list --network $PRIV_NET_ID --tags $PRIV_PORT_NAME -c id -f value)

openstack volume create --image $IMAGE_NAME --size $FLAVOR_DISK --bootable \
    $SERVER_NAME

# volume create has no --wait flag
while [ "$(openstack volume show $SERVER_NAME -c status -f value)" != "available" ]
    do sleep 5
done

# Assemble the user-data
# This is necessary because up until cloud-init 18.3, network configuration
# data sent by OpenStack wasn't used. This meant that only one NIC was usable.
# RHEL 7.6 is slated to ship 18.2.
# https://github.com/cloud-init/cloud-init/commit/cd1de5f
# https://bugs.launchpad.net/cloud-init/+bug/1749717
cat << USER_DATA > /tmp/user-data.txt
#!/usr/bin/env bash
cat << IFCFG > /etc/sysconfig/network-scripts/ifcfg-eth1
DEVICE="eth1"
ONBOOT=yes
HWADDR=$(openstack port list --tags $PROVIDER_PORT_NAME -c "MAC Address" -f value)
TYPE=Ethernet
BOOTPROTO=static
IPADDR=$PROVIDER_NET_IP
$(ipcalc --netmask $PROVIDER_NET_CIDR)
IFCFG
ifup eth1
USER_DATA

openstack server create --flavor $FLAVOR_NAME --volume $SERVER_NAME \
                        --key-name $KEYPAIR_NAME \
                        --nic port-id=$PRIV_PORT_ID \
                        --nic port-id=$PROVIDER_PORT_ID \
                        --security-group $SEC_GROUP_NAME \
                        --user-data /tmp/user-data.txt \
                        --wait $SERVER_NAME

echo "Success! Please allow a few minutes for the instance to boot and initialize before proceeding."
echo "Once the instance is fully up, you should be able to use the following command to access it:"
echo "ssh -i ~/$KEYPAIR_NAME.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $USER_NAME@$FLOAT_IP"
