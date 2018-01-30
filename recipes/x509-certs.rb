user = 'root'
group = 'root'
ip = node['ipaddress']
hostname = node['hostname']
cert_dir = node['cert_dir']

ca_cert = Base64.decode64 node['ca-cert']
ca_key = Base64.decode64 node['ca-key']
serviceaccount_key = Base64.decode64 node['serviceaccount-key']

key_usage = 'nonRepudiation, digitalSignature, keyEncipherment'
basic_constraints = 'CA:FALSE'
subject = "/CN=#{hostname}"
min_validity = 30 * 24 * 60 * 60 # 30 days
subject_alt_name = [
  "IP:127.0.0.1",
  "IP:10.255.0.1",
  "IP:#{ip}",
  "DNS:localhost",
  "DNS:#{hostname}"
]


directory "#{cert_dir}" do 
  recursive true
  owner user
  group user
  mode '0755'
end

file "#{cert_dir}/ca-cert.pem" do 
  content ca_cert
  owner user
  group user
  mode '0644'
end

k8s_cb_x509_certificate 'node' do
  action [:create, :update]
  ca_cert ca_cert
  ca_key  ca_key
  cert_dst "#{cert_dir}/#{hostname}-cert.pem"
  key_dst "#{cert_dir}/#{hostname}-key.pem"
  subject subject
  basic_constraints basic_constraints
  key_usage key_usage
  subject_alt_name subject_alt_name
  min_validity min_validity
end

file "#{cert_dir}/serviceaccount-key.pem" do
  content serviceaccount_key
  owner user
  group user
  mode '0644'
end
