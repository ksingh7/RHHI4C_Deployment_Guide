#!/bin/bash
source ~/stackrc
time openstack overcloud deploy \
   --templates /usr/share/openstack-tripleo-heat-templates \
   -n /home/stack/templates/network_data_ceph_metrics.yaml \
   --stack overcloud \
   -r /home/stack/templates/roles_data.yaml \
   -e /usr/share/openstack-tripleo-heat-templates/environments/network-isolation.yaml \
   -e /usr/share/openstack-tripleo-heat-templates/environments/ceph-ansible/ceph-ansible.yaml \
   -e /home/stack/templates/overcloud_images.yaml \
   -e /home/stack/templates/network-environment.yaml \
   -e /home/stack/templates/global-config.yaml \
   -e /home/stack/templates/disable-telemetry.yaml \
   -e /home/stack/templates/ceph-config.yaml \
   -e /home/stack/templates/cephmetrics.yaml > /tmp/overcloud.logs 2>&1
