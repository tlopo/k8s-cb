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
    file = "#{k8s_binary_dir}/#{::File.basename(k8s_node_binaries_url)}" 
    command  "tar -xvzf #{file} -C #{k8s_binary_dir} kubernetes/node/bin/#{file} --xform='s,.*/,,'"
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


