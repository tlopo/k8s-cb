user = 'root'
group = 'root'
k8s_manifest_dir = '/opt/kubernetes/manifests'

directory k8s_manifest_dir do 
  recursive true
  owner user
  group group
  mode '0755'
end

templates = {
  'kube-dns.yaml.erb' => 'deploy/kube-dns' 
  'calico-kubernetes-controller.yaml.erb' => 'deploy/calico-kubernetes-controller'
}

templates.each_key do |template|
  template "#{k8s_manifest_dir}/#{template.gsub(/.erb$/,'')}" do 
    source template
    owner user
    group group
    mode '0644'
  end
end

ruby_block 'Create add-ons' do
  block do
    Chef::Log.info 'Wait until cluster is functional'
    (1..10).each do
      `curl localhost:8080/healthz -sf`
       break if $?.success?

       Chef::Log.info 'Wait until cluster is functional'
       sleep 3
    end
    Chef::Log.info 'Kubernetes is up' if $?.success?
    raise 'Cluster is not functional' unless $?.success?


    templates.each_key do |template|
      template = template.gsub(/.erb$/,'')
      Chef::Log.info "Processing #{template}"
      cmd= [ "kubectl --namespace kube-system get #{templates[template]} ||",
             "kubectl replace --force -f #{k8s_manifest_dir}/#{template} --validate=false"].join(' ')
      out = `#{cmd}`
      Chef::Log.error out unless $?.success?
      raise "#{template} failed" unless $?.success?
    end

  end
end
