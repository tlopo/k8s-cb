user = 'root'
group = 'root'
ip = node['ipaddress']
hostname = node['hostname']
cert_dir = node['cert_dir']

is_etcd = false
is_master = false
is_minion = false

etcd_servers = node['etcd']['servers']
masters = node['kubernetes']['master']
minions = node['kubernetes']['minion']

etcd_servers.keys.each {|k| is_etcd = true if etcd_servers[k] == ip}
masters.keys.each {|k| is_master = true if masters[k] == ip}
minions.keys.each {|k| is_minion = true if minions[k] == ip}

k8s_node_binaries_url = 'https://dl.k8s.io/v1.9.2/kubernetes-node-linux-amd64.tar.gz'
k8s_binary_dir = '/opt/kubernetes/bin'
kubeconfig = '/opt/kubernetes/kubeconfig'

etcd_image = 'quay.io/coreos/etcd:v3.3'
etcd_tls = node['etcd']['tls']
etcd_scheme = etcd_tls ? 'https' : 'http'
etcd_servers = node['etcd']['servers'].values.map{|v| "#{etcd_scheme}://#{v}:2379" }.join(',')

hyperkube_image = 'gcr.io/google_containers/hyperkube-amd64:v1.9.2'
master_vip = node['kubernetes']['master_vip']
cluster_service_ip_range = node['kubernetes']['cluster_service_ip_range']
network_driver = node['network']['driver']
cluster_domain = node['kubernetes']['cluster_domain']
cluster_dns = node['kubernetes']['cluster_dns']
ha_minions = node['kubernetes']['minion-ha']
is_ha_minion = false
ha_minions.each_key {|k| is_ha_minion = true if ha_minions[k] == ip}

ip_in_ip_mtu = node['calico']['ip_in_ip_mtu']
ip_in_ip_mode = node['calico']['ip_in_ip_mode']
ip_pool = node['calico']['network']
