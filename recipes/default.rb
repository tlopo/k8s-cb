#
# Cookbook:: k8s-cb
# Recipe:: default
#
# Copyright:: 2018, The Authors, All Rights Reserved.

docker_service 'default'  do 
  action [:create, :start]
end

file '/etc/k8s' do
  content 'Kubernetes cookbook run'
end
