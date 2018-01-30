user = 'root'
group = 'root'
k8s_manifest_dir = '/opt/kubernetes/manifests'

directory k8s_manifest_dir do 
  recursive true
  owner user
  group group
  mode '0755'
end

template "#{k8s_manifest_dir}/kube-dns.yaml" do 
  source 'kube-dns.yaml.erb'
  owner user
  group group
  mode '0644'
end


