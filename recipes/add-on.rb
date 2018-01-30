user = 'root'
group = 'root'
k8s_manifest_dir = '/opt/kubernetes/manifests'

directory k8s_manifest_dir do 
  recursive true
  owner user
  group group
  mode '0755'
end

templates = [
  "kube-dns.yaml.erb"
] 


templates.each do |template|
  template "#{k8s_manifest_dir}/#{template.gsub(/.erb$/,'')}" do 
    source template
    owner user
    group group
    mode '0644'
  end
end
