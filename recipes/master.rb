user = 'root'
group = 'root'
ip = node['ipaddress']
hostname = node['hostname']
cert_dir = node['cert_dir']

k8s_node_binaries_url = 'https://dl.k8s.io/v1.9.2/kubernetes-node-linux-amd64.tar.gz'
k8s_binary_dir = '/opt/kubernetes/bin'
kubeconfig = '/opt/kubernetes/kubeconfig'

hyperkube_image = 'gcr.io/google_containers/hyperkube-amd64:v1.9.2'
master_vip = node['kubernetes']['master_vip'] 
cluster_service_ip_range = node['kubernetes']['cluster_service_ip_range']

etcd_tls = node['etcd']['tls']
etcd_scheme = etcd_tls ? 'https' : 'http'
etcd_servers = node['etcd']['servers'].values.map{|v| "#{etcd_scheme}://#{v}:2379" }.join(',')

masters = node['kubernetes']['master']
first_master = masters[masters.keys.first] == node['ipaddress']

network_driver = node['network_driver']
#include_recipe "#{cookbook_name}::calico" if network_driver == 'calico'

directory k8s_binary_dir do
  recursive true
  user user
  group group
  mode '0755'
end

remote_file "#{k8s_binary_dir}/#{::File.basename(k8s_node_binaries_url)}" do 
  source k8s_node_binaries_url
end

log 'debug file' do 
  message "File => #{k8s_binary_dir}/#{::File.basename(k8s_node_binaries_url)}"
  level :error
end

execute 'extract_kubectl' do
  file = "#{k8s_binary_dir}/#{::File.basename(k8s_node_binaries_url)}" 
  command  "tar -xvzf #{file} -C #{k8s_binary_dir} kubernetes/node/bin/kubectl --xform='s,.*/,,'"
  not_if { ::File.exists? "#{k8s_binary_dir}/kubectl" }
end

['kubectl'].each do |file|
  link "/usr/bin/#{file}" do
    to "/opt/kubernetes/bin/#{file}"
  end
end

template "#{kubeconfig}" do 
  source 'kubeconfig.erb'
  owner user
  group group
  mode '0644'
end

systemd_unit 'kube-apiserver.service'  do
  cmd = [
        '/usr/bin/docker run --rm',
        "-v #{cert_dir}:#{cert_dir}",
        "--net host --name %n #{hyperkube_image} kube-apiserver",
        '--insecure-port=8080',
        '--insecure-bind-address=127.0.0.1',
        "--advertise-address=#{master_vip}",
        "--bind-address=#{ip}",
        "--v=4",
        '--apiserver-count=2',
        "--service-cluster-ip-range=#{cluster_service_ip_range}",
        "--tls-cert-file=#{cert_dir}/#{hostname}-cert.pem",
        "--tls-private-key-file=#{cert_dir}/#{hostname}-key.pem",
        "--client-ca-file=#{cert_dir}/ca-cert.pem",
        "--service-account-key-file=#{cert_dir}/serviceaccount-key.pem",
        '--admission-control=NamespaceLifecycle,LimitRanger,ServiceAccount,ResourceQuota',
        "--etcd-servers=#{etcd_servers}"
  ]

  if etcd_tls 
    cmd << "--etcd-cafile=#{cert_dir}/ca-cert.pem"
    cmd << "--etcd-certfile=#{cert_dir}/#{hostname}-cert.pem"
    cmd << "--etcd-keyfile=#{cert_dir}/#{hostname}-key.pem"
  end

  content <<-EOF.gsub(/^  /,'')
  [Unit]
  Description=Kubernetes API Server
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
  notifies :restart, 'service[kube-apiserver]', :delayed
  action [:create, :enable]
end

service 'kube-apiserver' do
  action [:start, :enable]
end

systemd_unit 'kube-scheduler.service'  do
  content <<-EOF.gsub(/^  /,'')
  [Unit]
  Description=Kubernetes Scheduler
  After=docker.service
  Requires=docker.service
   
  [Service]
  TimeoutStartSec=0
  Restart=always
  ExecStartPre=-/usr/bin/docker stop %n
  ExecStartPre=-/usr/bin/docker rm %n
  ExecStart=/usr/bin/docker run --rm\
        -v #{cert_dir}:#{cert_dir} \
        -v #{kubeconfig}:#{kubeconfig}\
        --net host --name %n #{hyperkube_image} kube-scheduler\
        --kubeconfig=#{kubeconfig} --leader-elect

  ExecStop=/usr/bin/docker stop %n
  Restart=always
  RestartSec=10s
  NotifyAccess=all
  
  [Install]
  WantedBy=multi-user.target
  EOF
  notifies :restart, 'service[kube-scheduler]', :delayed
  action [:create, :enable]
end

service 'kube-scheduler' do
  action [:start, :enable]
end

systemd_unit 'kube-controller-manager.service'  do
  content <<-EOF.gsub(/^  /,'')
  [Unit]
  Description=Kubernetes Controller Manager
  After=docker.service
  Requires=docker.service
   
  [Service]
  TimeoutStartSec=0
  Restart=always
  ExecStartPre=-/usr/bin/docker stop %n
  ExecStartPre=-/usr/bin/docker rm %n
  ExecStart=/usr/bin/docker run --rm \
        -v #{cert_dir}:#{cert_dir} \
        -v #{kubeconfig}:#{kubeconfig}\
        --net host --name %n #{hyperkube_image} kube-controller-manager \
        --root-ca-file=#{cert_dir}/ca-cert.pem \
        --service_account_private_key_file=#{cert_dir}/serviceaccount-key.pem \
        --kubeconfig=/opt/kubernetes/kubeconfig --leader-elect

  ExecStop=/usr/bin/docker stop %n
  Restart=always
  RestartSec=10s
  NotifyAccess=all
  
  [Install]
  WantedBy=multi-user.target
  EOF
  notifies :restart, 'service[kube-controller-manager]', :delayed
  action [:create, :enable]
end

service 'kube-controller-manager' do
  action [:start, :enable]
end


include_recipe "#{cookbook_name}::add-on" if first_master
