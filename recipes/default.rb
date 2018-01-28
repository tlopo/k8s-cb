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


Chef::Log.info "DIR => #{__dir__}"

#include_recipe "#{cookbook_name}::x509-certs"
