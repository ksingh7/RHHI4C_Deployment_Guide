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

openstack security group create $SEC_GROUP_NAME
# Open the SSH port
openstack security group rule create --ingress --protocol tcp \
                                     --dst-port 22 $SEC_GROUP_NAME
# Open Grafana's port
openstack security group rule create --ingress --protocol tcp \
                                     --dst-port 3000 $SEC_GROUP_NAME
# Open Prometheus' port
openstack security group rule create --ingress --protocol tcp \
                                     --dst-port 9090 $SEC_GROUP_NAME
# Open node_exporter's port
openstack security group rule create --ingress --protocol tcp \
                                     --dst-port 9100 $SEC_GROUP_NAME
# Allow pings
openstack security group rule create --ingress --protocol icmp $SEC_GROUP_NAME
openstack security group rule create --egress $SEC_GROUP_NAME

# Create the private network and subnet
openstack network create $PRIV_NET_NAME
PRIV_NET_ID=$(openstack network show $PRIV_NET_NAME -c id -f value)
openstack subnet create --network $PRIV_NET_NAME $PRIV_SUBNET_NAME \
                        --dns-nameserver $DNS_IP \
                        --subnet-range $PRIV_NET_CIDR
# For some reason, we need to capitalize ID here and nowhere else
PRIV_SUBNET_ID=$(openstack subnet list --network $PRIV_NET_ID -c ID -f value)

# Create the private port
openstack port create $PRIV_PORT_NAME --network $PRIV_NET_ID \
                      --fixed-ip subnet=$PRIV_SUBNET_NAME \
                      --security-group $SEC_GROUP_NAME \
                      --tag $PRIV_PORT_NAME
PRIV_PORT_ID=$(openstack port list --network $PRIV_NET_ID --tags $PRIV_PORT_NAME -c id -f value)

# Create a router and use it to connect the public and private networks
openstack router create $ROUTER_NAME
openstack router set $ROUTER_NAME --external-gateway $PUB_NET_NAME
openstack router add subnet $ROUTER_NAME $PRIV_SUBNET_NAME

# Create the floating IP that we will use for the instance
openstack floating ip create --port $PRIV_PORT_ID --floating-ip-address $FLOAT_IP $PUB_NET_NAME

# Create the provider network and subnet
openstack network create $PROVIDER_NET_NAME --provider-physical-network $PROVIDER_PHYSICAL_NET  \
                                            --provider-network-type $PROVIDER_NET_TYPE \
                                            --provider-segment $PROVIDER_SEGMENT \
                                            --share
PROVIDER_NET_ID=$(openstack network show $PROVIDER_NET_NAME -c id -f value)
openstack subnet create $PROVIDER_SUBNET_NAME --network $PROVIDER_NET_NAME \
                        --subnet-range $PROVIDER_NET_CIDR \
                        --allocation-pool $PROVIDER_NET_ALLOCATION_POOL \
                        --no-dhcp
# For some reason, we need to capitalize ID here and nowhere else
PROVIDER_SUBNET_ID=$(openstack subnet list --network $PROVIDER_NET_ID -c ID -f value)

# Create the provider port
openstack port create $PROVIDER_PORT_NAME --network $PROVIDER_NET_ID \
                      --fixed-ip subnet=$PROVIDER_SUBNET_NAME,ip-address=$PROVIDER_NET_IP \
                      --security-group $SEC_GROUP_NAME --project $PROJECT_NAME \
                      --tag $PROVIDER_PORT_NAME
PROVIDER_PORT_ID=$(openstack port list --network $PROVIDER_NET_ID --tags $PROVIDER_PORT_NAME -c id -f value)

# Create the flavor
openstack flavor create $FLAVOR_NAME --disk $FLAVOR_DISK --vcpus $FLAVOR_CPUS --ram $FLAVOR_RAM

# Create a volume with the same name as the server; when we create the server
# using this volume, our data will persist across reboots.
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
