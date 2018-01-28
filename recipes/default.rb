# Cookbook:: k8s_cb
# Recipe:: default
# Copyright:: 2018, The Authors, All Rights Reserved.


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

unless is_etcd or is_master or is_minion
  Chef::Log.warn "#{hostname} does not belong to any of the following groups [minion, master, etcd]"
  return 
end

yum_package 'docker'

service 'docker'  do 
  action :start
end

service 'docker' do
  action :enable
end

include_recipe "#{cookbook_name}::x509-certs"
include_recipe "#{cookbook_name}::etcd" if is_etcd
include_recipe "#{cookbook_name}::master" if is_master
include_recipe "#{cookbook_name}::master" if is_minion
