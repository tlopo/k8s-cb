user = 'root'
group = 'root'
ip = node['ipaddress']
hostname = node['hostname']
cert_dir = node['cert_dir']

etcd_image = 'quay.io/coreos/etcd:v3.3'
etcd_tls = node['etcd']['tls']
etcd_scheme = etcd_tls ? 'https' : 'http'
etcd_servers = node['etcd']['servers'].values.map{|v| "#{etcd_scheme}://#{v}:2379" }.join(',')

user user do 
  uid uid
  shell '/bin/false'
end

directory '/opt/etcd/data' do
  recursive true
  owner user
  group user
  mode '0755'
end

directory '/opt/etcd/config' do
  recursive true
  owner user
  group user
  mode '0755'
end

template '/opt/etcd/config/etcd.yml' do 
  source 'etcd.yml.erb'
  owner user
  group user
  mode '0644'
  notifies :restart, 'service[etcd]', :delayed
end

systemd_unit 'etcd.service'  do 
  cmd = [
    '/usr/bin/docker run --rm',
    "-v #{cert_dir}:#{cert_dir}",
    '-v /opt/etcd/config/etcd.yml:/opt/etcd/config/etcd.yml',
    '-v /opt/etcd/data:/opt/etcd/data',
    "-u root --net host --name %n #{etcd_image}",
    'etcd --config-file /opt/etcd/config/etcd.yml' 
  ]
  content <<-EOF.gsub(/^ {2}/,'')
  [Unit]
  Description=Etcd Container
  After=docker.service
  Requires=docker.service
   
  [Service]
  TimeoutStartSec=0
  Restart=always
  ExecStartPre=-/usr/bin/docker stop %n
  ExecStartPre=-/usr/bin/docker rm %n
  ExecStart=#{cmd.join(' ')}

  ExecStop=/usr/bin/docker stop %n
  Restart=always
  RestartSec=10s
  NotifyAccess=all
  
  [Install]
  WantedBy=multi-user.target
  EOF
  action [:create, :enable]
end

service 'etcd' do
  action [:start, :enable]
end

file '/opt/etcd/etcdctl' do 
  cmd = [ 
    "sudo docker exec  -i etcd.service etcdctl"
  ]
  if etcd_tls 
    cmd << "--cert-file #{cert_dir}/#{hostname}-cert.pem"
    cmd << "--key-file #{cert_dir}/#{hostname}-key.pem"
    cmd << "--ca-file #{cert_dir}/ca-cert.pem"
  end
  cmd << "--endpoint #{etcd_scheme}://127.0.0.1:2379"
  cmd << '$@'
  content <<-EOC.gsub(/^\s+/,'')
    #! /bin/bash
    #{cmd.join(' ')}
  EOC
  owner user
  group user
  mode '0755'
end

