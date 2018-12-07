#!/usr/bin/env python
import argparse
import json
import os
import yaml


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "file",
        nargs=1,
    )
    parser.add_argument(
        "-i", "--input-format",
        choices=["tripleo", "ceph-ansible"],
        default="tripleo",
    )
    parser.add_argument(
        "-f", "--format",
        choices=["hosts", "raw", "yaml"],
        default="yaml",
    )
    parser.add_argument(
        "-a", "--add-host",
        help="Optionally add a host to the inventory using information in "
             "create.sh format",
    )
    return parser.parse_args()


def load_file(path):
    """
    Reads a file, and based on its extension, attempts to parse it and return
    the representing object. Supports:
    * YAML: .yaml, .yaml
    * JSON: .json
    * Shell-style environment variables (e.g. 'FOO=x\\nBAR=y'): .conf
    """
    ext = None
    if '.' in path:
        ext = path.split('.')[-1]
    with open(path) as f:
        contents = f.read()
    if ext in ('yaml', 'yml'):
        return yaml.safe_load(contents)
    elif ext == 'json':
        return json.loads(contents)
    elif ext == 'conf':
        result = dict()
        # Here we just extract key-value pairs while ignoring comments.
        for line in contents.strip().split('\n'):
            if not line:
                continue
            if line.strip().startswith('#'):
                continue
            key, value = line.split('=', 1)
            # Make sure to catch inline comments, too
            if '#' in value:
                value = value.split('#')[0].strip()
            result[key] = value
        return result
    elif ext is None:
        raise NotImplementedError


def simplify_tripleo_inventory(orig_obj):
    """
    Accepts an object generated by:
      tripleo-ansible-inventory --static-yaml-inventory inventory.yaml
    Since the TripleO inventory isn't quite in the format we'd expect, it must
    rearrange it to:
      1. Use group names that cephmetrics and ceph-ansible look for, e.g.
         'mgrs', 'osds'
      2. Attach 'ansible_ssh_user=heat-admin' to the Ceph nodes as a var
      3. Attach 'ansible_host=<ctlplane_ip>' to the Ceph nodes as a var
      4. Attach 'cephmetrics_ip=<cephmetrics_ip> to the Ceph nodes as a var
    """
    group_map = dict(
      Controller=['mons', 'mgrs'],
      CephStorage=['osds'],
    )
    new_obj = dict(
        all=dict(),
    )
    for orig_group_name, new_group_names in group_map.items():
        temp_group = dict()
        orig_group = orig_obj.get(orig_group_name)
        if orig_group is None:
            continue
        if 'children' in orig_group:
            for child_name in orig_group['children'].keys():
                temp_group[child_name] = orig_obj[child_name]['vars']
        elif 'hosts' in orig_group:
            for child_name in orig_group['hosts'].keys():
                temp_group[child_name] = orig_group['hosts'][child_name]
        for child_name, child_vars in temp_group.items():
            new_obj['all'].setdefault('hosts', dict())[child_name] = dict(
                ansible_host=child_vars['ctlplane_ip'],
                ansible_ssh_user='heat-admin',
                cephmetrics_ip=child_vars['cephmetrics_ip'],
            )
            for new_group_name in new_group_names:
                new_obj.setdefault(new_group_name, dict()).setdefault(
                    'hosts', dict())[child_name] = dict()
    return new_obj


def format_hosts_dict(inventory_obj):
    """
    For each group in the inventory, assemble all hosts with either a
    cephmetrics_ip var or an ansible_host var. Return a dict mapping their
    names to the cephmetrics_ip value if found, or the ansible_host value if
    not.
    """
    hosts_obj = dict()
    for group_name, group in inventory_obj.items():
        for host_name, host in group.get('hosts', dict()).items():
            if 'cephmetrics_ip' in host:
                hosts_obj[host_name] = host['cephmetrics_ip']
            elif 'ansible_host' in host:
                hosts_obj[host_name] = host['ansible_host']
    return hosts_obj


def format_hosts(inventory_obj):
    """
    Using format_hosts_dict(), return an /etc/hosts fragment.
    """
    hosts_obj = format_hosts_dict(inventory_obj)
    return reduce(
        lambda x, y: "\n".join([x, y]),
        map(
            lambda x: " ".join(x[::-1]),
            hosts_obj.items(),
        ),
    )


def add_host(inventory, host_conf):
    """
    Given an Ansible inventory object, use the provided host_conf object to
    add an entry for the host. Also, ensure that the host is added to the
    specified group, with 'ceph-grafana' being the default.
    """
    host_obj = dict(
        ansible_host=host_conf['FLOAT_IP'],
        ansible_ssh_common_args="-o StrictHostKeyChecking=no "
                                "-o UserKnownHostsFile=/dev/null",
        ansible_ssh_private_key_file=os.path.expanduser(
            '~/%s.pem' % host_conf['KEYPAIR_NAME']),
        ansible_ssh_user=host_conf['USER_NAME'],
    )
    server_name = host_conf['SERVER_NAME']
    inventory.setdefault('all', dict()).\
        setdefault('hosts', dict())[server_name] = host_obj
    group_name = host_conf.get('GROUP_NAME', 'ceph-grafana')
    inventory.setdefault(group_name, dict()).\
        setdefault('hosts', dict())[server_name] = dict()
    return inventory


def add_vars(inventory):
    """
    Given an Ansible inventory object, adds the following to the 'all' group
    vars:
      * A ['prometheus']['etc_hosts'] object containing host->IP mappings for
        all nodes in the inventory which also have an 'ansible_host' var
      * A ['grafana']['admin_password'] string set to 'admin'
    """
    etc_hosts = format_hosts_dict(inventory)
    inventory.setdefault('all', dict()).\
        setdefault('vars', dict()).\
        setdefault('prometheus', dict())['etc_hosts'] = etc_hosts
    inventory['all']['vars'].\
        setdefault('grafana', dict())['admin_password'] = 'admin'
    return inventory


if __name__ == "__main__":
    args = parse_args()

    orig_obj = load_file(args.file[0])

    if args.input_format == "tripleo":
        inv = simplify_tripleo_inventory(orig_obj)
    elif args.input_format == "ceph-ansible":
        inv = orig_obj

    if args.add_host:
        new_host_conf = load_file(args.add_host)
        add_host(inv, new_host_conf)

    add_vars(inv)

    if args.format == "yaml":
        print yaml.safe_dump(inv, default_flow_style=False)
    elif args.format == "hosts":
        print format_hosts(inv)
    elif args.format == "raw":
        print inv