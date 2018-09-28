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
PROJECT_RC="$HOME/${PROJECT_NAME}rc"

. $ADMIN_RC
PROVIDER_NET_ID=$(openstack network show $PROVIDER_NET_NAME -c id -f value)
PROVIDER_PORT_ID=$(openstack port list --network $PROVIDER_NET_ID --tags $PROVIDER_PORT_NAME -c id -f value)

. $PROJECT_RC
PRIV_NET_ID=$(openstack network show $PRIV_NET_NAME -c id -f value)
PRIV_PORT_ID=$(openstack port list --network $PRIV_NET_ID --tags $PRIV_PORT_NAME -c id -f value)
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
