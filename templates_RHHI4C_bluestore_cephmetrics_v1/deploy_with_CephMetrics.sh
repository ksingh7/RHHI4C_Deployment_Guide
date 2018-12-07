#!/bin/bash
source ~/stackrc
time openstack overcloud deploy \
   --templates /home/stack/templates/ceph_metrics_ops_THT  \
   -n /home/stack/templates/ceph_metrics_ops_THT_2/network_data_ceph_metrics.yaml \
   --stack overcloud \
   -r /home/stack/templates/roles_data.yaml \
   -e /home/stack/templates/ceph_metrics_ops_THT/environments/network-isolation.yaml \
   -e /home/stack/templates/ceph_metrics_ops_THT/environments/ceph-ansible/ceph-ansible.yaml \
   -e /home/stack/templates/overcloud_images.yaml \
   -e /home/stack/templates/network-environment.yaml \
   -e /home/stack/templates/global-config.yaml \
   -e /home/stack/templates/disable-telemetry.yaml \
   -e /home/stack/templates/ceph-config.yaml \
   -e /home/stack/templates/cephmetrics.yaml > /tmp/overcloud.logs 2>&1

# Note that I removed 
#   -p /home/stack/templates/plan-environment-derived-params.yaml \

# Note as per https://bugs.launchpad.net/tripleo/+bug/1776987
# I updated disable-telemetry.yaml to be like this one:
# https://review.openstack.org/#/c/585911/1/environments/disable-telemetry.yaml
