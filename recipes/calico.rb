user = 'root'
group = 'root'
ip = node['ipaddress']
hostname = node['hostname']
cert_dir = node['cert_dir']

k8s_node_binaries_url = 'https://dl.k8s.io/v1.9.2/kubernetes-node-linux-amd64.tar.gz'
k8s_binary_dir = '/opt/kubernetes/bin'
kubeconfig = '/opt/kubernetes/kubeconfig'

ip_in_ip_mtu = node['calico']['ip_in_ip_mtu']
ip_in_ip_mode = node['calico']['ip_in_ip_mode']
ip_pool = node['calico']['network']

cni_bin_dir = '/opt/cni/bin/calico'
bin = {
  calico: {
    src: 'https://github.com/projectcalico/cni-plugin/releases/download/v2.0.0/calico',
    dst: "#{cni_bin_dir}/calico"
  },
  calico_ipam: {
    src: 'https://github.com/projectcalico/cni-plugin/releases/download/v2.0.0/calico-ipam',
    dst: "#{cni_bin_dir}/calico-ipam"
  },
  cni: {
    src: 'https://github.com/containernetworking/cni/releases/download/v0.3.0/cni-v0.3.0.tgz',
    dst: "#{cni_bin_dir}/cni-v0.3.0.tgz"
  },
  calico_ctl: {
    src: 'https://github.com/projectcalico/calicoctl/releases/download/v2.0.0/calicoctl',
    dst: '/opt/calico/bin/calicoctl'
  }
}


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

bin.each_key do |k|
  directory "#{::File.dirname bin[k][:dst]}"  do
    recursive true
    owner user
    group user
    mode '0755'
  end
end

bin.each_key do |k|
  remote_file bin[k][:dst] do
    source bin[k][:src]
  end
end

execute 'extract cni loopback' do
  command %Q[tar xvzf "#{cni_bin_dir}/#{::File.basename bin[:cni][:dst]}" -C #{cni_bin_dir} ./loopback]
  not_if { ::File.exists? "#{cni_bin_dir}/loopback" }
end

['/etc/cni/net.d','/etc/calico'].each do |dir|
  directory "#{dir}" do
    recursive true
    owner user
    group user
    mode '0755'
  end
end

file '/etc/calico/calicoctl.cfg' do
  lines = [
    'apiVersion: projectcalico.org/v3',
    'kind: CalicoAPIConfig',
    'metadata:',
    'spec:',
     "  etcdEndpoints: #{etcd_servers}"
  ]

  if etcd_tls
    lines << "  etcdKeyFile: #{cert_dir}/#{hostname}-key.pem"
    lines << "  etcdCertFile: #{cert_dir}/#{hostname}-cert.pem"
    lines << "  etcdCACertFile: #{cert_dir}/ca-cert.pem"
  end

  content lines.join("\n")
  owner user
  group user
  mode '0644'
end

systemd_unit 'calico.service'  do
  cmd = [
    '/usr/bin/docker run --net=host --privileged --name=calico-node',
    "--rm -e NODENAME=#{hostname}",
    "-e FELIX_IPV6SUPPORT=false -e IP=#{ip}",
    '-e FELIX_DEFAULTENDPOINTTOHOSTACTION=ACCEPT',
    "-e FELIX_IPINIPMTU=#{ip_in_ip_mtu}",
    "-e CALICO_IPV4POOL_CIDR=#{ip_pool}",
    "-e CALICO_IPV4POOL_IPIP=#{ip_in_ip_mode}",
    '-e CALICO_NETWORKING_BACKEND=bird -e CALICO_LIBNETWORK_ENABLED=true',
    "-e CALICO_K8S_NODE_REF=#{hostname}",
    '-e CLUSTER_TYPE=k8s,bgp',
    '-v /var/log/calico:/var/log/calico',
    '-v /var/run/calico:/var/run/calico',
    '-v /lib/modules:/lib/modules',
    '-v /run:/run -v /run/docker/plugins:/run/docker/plugins',
    '-v /var/run/docker.sock:/var/run/docker.sock',
    "-v #{cert_dir}/ca-cert.pem:/etc/calico/certs/ca_cert.crt",
    "-v #{cert_dir}/#{hostname}-key.pem:/etc/calico/certs/key.pem",
    "-v #{cert_dir}/#{hostname}-cert.pem:/etc/calico/certs/cert.crt"
  ]

  if etcd_tls
    cmd << '-e ETCD_CA_CERT_FILE=/etc/calico/certs/ca_cert.crt'
    cmd << '-e ETCD_KEY_FILE=/etc/calico/certs/key.pem'
    cmd << '-e ETCD_CERT_FILE=/etc/calico/certs/cert.crt'
  end

  cmd << "-e ETCD_ENDPOINTS=#{etcd_servers}"
  cmd << 'quay.io/calico/node:v3.0.1'

  content <<-EOF.gsub(/^  /,'')
  [Unit]
  Description=Calico Node
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
  notifies :restart, 'service[calico]', :delayed
  action [:create, :enable]
end

service 'calico' do
  action [:start, :enable]
end
