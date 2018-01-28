# Cookbook:: k8s_cb
# Recipe:: default
#
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
########

k8s_node_binaries_url = 'https://dl.k8s.io/v1.9.2/kubernetes-node-linux-amd64.tar.gz'
k8s_binary_dir = '/opt/kubernetes/bin'

directory k8s_binary_dir do
  recursive true
  user user
  group group
  mode '0755'
end

remote_file ::File.basename(k8s_node_binaries_url) do 
  source k8s_node_binaries_url
end

