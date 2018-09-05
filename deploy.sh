#!/bin/bash
source ~/stackrc
time openstack overcloud deploy \
   --templates /usr/share/openstack-tripleo-heat-templates \
   --stack overcloud \
   -r /home/stack/templates/roles_data.yaml \
   -e /usr/share/openstack-tripleo-heat-templates/environments/network-isolation.yaml \
   -e /usr/share/openstack-tripleo-heat-templates/environments/ceph-ansible/ceph-ansible.yaml \
   -e /home/stack/templates/overcloud_images.yaml \
   -e /home/stack/templates/network-environment.yaml \
   -e /home/stack/templates/global-config.yaml \
   -e /home/stack/templates/disable-telemetry.yaml \
   -e /home/stack/templates/ceph-config.yaml > /tmp/overcloud.logs 2>&1

# Note that I removed 
#   -p /home/stack/templates/plan-environment-derived-params.yaml \

# Note as per https://bugs.launchpad.net/tripleo/+bug/1776987
# I updated disable-telemetry.yaml to be like this one:
# https://review.openstack.org/#/c/585911/1/environments/disable-telemetry.yaml
