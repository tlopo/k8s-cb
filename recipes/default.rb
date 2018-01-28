# Cookbook:: k8s_cb
# Recipe:: default
# Copyright:: 2018, The Authors, All Rights Reserved.

yum_package 'docker'

service 'docker'  do 
  action :start
end

service 'docker' do
  action :enable
end

include_recipe "#{cookbook_name}::x509-certs"
user = 'root'
group = 'root'
ip = node['ipaddress']
hostname = node['hostname']
cert_dir = node['cert_dir']
k8s_node_binaries_url = 'https://dl.k8s.io/v1.9.2/kubernetes-node-linux-amd64.tar.gz'
k8s_binary_dir = '/opt/kubernetes/bin'
kubeconfig = '/opt/kubernetes/kubeconfig'
etcd_tls = node['etcd']['tls']
etcd_scheme = etcd_tls ? 'https' : 'http'
etcd_servers = node['etcd']['servers'].values.map{|v| "#{etcd_scheme}://#{v}:2379" }.join(',')
########

image = 'gcr.io/google_containers/hyperkube-amd64:v1.9.2'
master_vip = node['kubernetes']['master_vip'] 
cluster_service_ip_range = node['kubernetes']['cluster_service_ip_range']
network_driver = node['network']['driver']
cluster_domain = node['kubernetes']['cluster_domain']
cluster_dns = node['kubernetes']['cluster_dns']
ha_minions = node['kubernetes']['minion-ha']
is_ha_minion = false
ha_minions.each_key {|k| is_ha_minion = true if ha_minions[k] == ip}


directory k8s_binary_dir do
  recursive true
  user user
  group group
  mode '0755'
end

remote_file "#{k8s_binary_dir}/#{::File.basename(k8s_node_binaries_url)}" do 
  source k8s_node_binaries_url
end

['kubelet','kube-proxy','kubectl'].each do |file|
  execute "extract_#{file}" do
    tgz_file = "#{k8s_binary_dir}/#{::File.basename(k8s_node_binaries_url)}" 
    command  "tar -xvzf #{tgz_file} -C #{k8s_binary_dir} kubernetes/node/bin/#{file} --xform='s,.*/,,'"
    not_if { ::File.exists? "#{k8s_binary_dir}/#{file}" }
  end
  
  ['kubectl'].each do |file|
    link "/usr/bin/#{file}" do
      to "/opt/kubernetes/bin/#{file}"
    end
  end
end

template "#{kubeconfig}" do 
  source 'kubeconfig.erb'
  owner user
  group group
  mode '0644'
end

execute 'disable_swap' do
  command 'swapoff -a'
  only_if 'swapon -s | grep -qPo "\d+"'
end

execute 'remove_swap_from_fstab' do
  command 'sed -ri "/swap/d" /etc/fstab'
  only_if 'grep swap /etc/fstab'
end

systemd_unit 'kubelet.service'  do
  cmd = [
    '/opt/kubernetes/bin/kubelet',
    '--address=0.0.0.0',
    "--kubeconfig=#{kubeconfig}",
    "--cluster-domain=#{cluster_domain}",
    "--cluster-dns=#{cluster_dns}"
  ]

  cmd << '--node-labels=ha-minion=true' if is_ha_minion

  if network_driver == 'calico'
    cmd << '--network-plugin=cni'
    cmd << '--cni-conf-dir=/etc/cni/net.d'
    cmd << '--cni-bin-dir=/opt/cni/bin'
  end

  content <<-EOF.gsub(/^  /,'')
  [Unit]
  Description=Kubelet
  After=docker.service
  Requires=docker.service
   
  [Service]
  TimeoutStartSec=0
  Restart=always
  ExecStart=#{cmd.join(' ')}
  ExecStop=/bin/kill $MAINPID
  Restart=always
  RestartSec=10s
  NotifyAccess=all
  
  [Install]
  WantedBy=multi-user.target
  EOF
  notifies :restart, 'service[kubelet]', :delayed
  action [:create, :enable]
end

service 'kubelet' do
  action [:start, :enable]
end

service 'kubelet' do
  action [:start, :enable]
end

systemd_unit 'kube-proxy.service'  do
  cmd = [
    '/opt/kubernetes/bin/kube-proxy',
    "--master=#{api_servers}",
    '--proxy-mode=iptables',
    '--kubeconfig /opt/kubernetes/kubeconfig'
  ]
  content <<-EOF.gsub(/^  /,'')
  [Unit]
  Description=Kube-proxy
  After=docker.service
  Requires=docker.service
   
  [Service]
  TimeoutStartSec=0
  Restart=always
  ExecStart=#{cmd.join(' ')}
  ExecStop=/bin/kill $MAINPID
  Restart=always
  RestartSec=10s
  NotifyAccess=all
  
  [Install]
  WantedBy=multi-user.target
  EOF
  notifies :restart, 'service[kube-proxy]', :delayed
  action [:create, :enable]
end

service 'kube-proxy' do
  action [:start, :enable]
end
