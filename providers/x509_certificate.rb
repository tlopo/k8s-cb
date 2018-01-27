require 'openssl'

def whyrun_supported?
  true
end

use_inline_resources

def generate(opts)
  CertGen.new({
    ca_cert: opts[:ca_cert],
    ca_key: opts[:ca_key],
    subject: opts[:subject],
    subject_alt_name: opts[:subject_alt_name],
    basic_constraints: opts[:basic_constraints],
    key_usage: opts[:key_usage],
    min_validity: opts[:min_validity],
  }).generate
end

def pretty_csv(str)
  str.gsub(/\s*,\s*/,', ')
end

action :create do
  opts = {
    ca_cert: @new_resource.ca_cert,
    ca_key: @new_resource.ca_key,
    cert_dst: @new_resource.cert_dst,
    key_dst: @new_resource.key_dst,
    subject: OpenSSL::X509::Name.parse(@new_resource.subject).to_s,
    subject_alt_name: pretty_csv(@new_resource.subject_alt_name),
    basic_constraints: @new_resource.basic_constraints,
    key_usage: @new_resource.key_usage,
    min_validity: @new_resource.min_validity,
  }

  if ::File.exists? opts[:cert_dst]
    Chef::Log.info "Files '#{opts[:cert_dst]}' and '#{opts[:key_dst]}' already created"
    return 
  end

  converge_by "Generating '#{opts[:cert_dst]}' and '#{opts[:key_dst]}'" do  
    cert = generate opts
 
    file "#{opts[:cert_dst]}" do 
      content cert[:cert]
    end
   
    file "#{opts[:key_dst]}" do 
      content cert[:key]
    end
    
    log 'success' do
      message "Generated '#{opts[:cert_dst]}' and '#{opts[:key_dst]}' successfully"
      level :info
    end  
  end
end

action :update do 
  # Update if subject, key_usage, basic_constraints or subject_alt_name changes 
  # Update if not_after - Time.now > min_validity

  opts = {
    ca_cert: @new_resource.ca_cert,
    ca_key: @new_resource.ca_key,
    cert_dst: @new_resource.cert_dst,
    key_dst: @new_resource.key_dst,
    subject: OpenSSL::X509::Name.parse(@new_resource.subject).to_s,
    subject_alt_name: pretty_csv(@new_resource.subject_alt_name),
    basic_constraints: @new_resource.basic_constraints,
    key_usage: @new_resource.key_usage,
    min_validity: @new_resource.min_validity,
  }

  unless ::File.exists? opts[:cert_dst] and ::File.exists? opts[:key_dst]
    Chef::Log.info  "Files '#{opts[:cert_dst]}' and '#{opts[:key_dst]}' do not exist yet"
    return 
  end

  cr = CertReader.new ::File.read opts[:cert_dst]

  min_validity = opts[:min_validity] ? opts[:min_validity] : 30 * 24 * 60 * 60
  time_left = cr.fetch_not_after - Time.now
  list = []
 
  subject = opts[:subject]
  key_usage = OpenSSL::X509::ExtensionFactory.new.create_extension('keyUsage', opts[:key_usage]).to_a[1]
  basic_constraints = OpenSSL::X509::ExtensionFactory.new.create_extension('basicConstraints',opts[:basic_constraints]).to_a[1]
  subject_alt_name = OpenSSL::X509::ExtensionFactory.new.create_extension('subjectAltName', opts[:subject_alt_name]).to_a[1]

  list <<  [:subject, subject, cr.fetch_subject, proc { subject != cr.fetch_subject} ]
  list << [:key_usage, key_usage, cr.fetch_key_usage[1], proc { key_usage && key_usage != cr.fetch_key_usage[1]}]
  list << [:basic_constraints, basic_constraints, cr.fetch_basic_constraints[1], proc {basic_constraints && basic_constraints != cr.fetch_basic_constraints[1]}]
  list << [:subject_alt_name, subject_alt_name, cr.fetch_subject_alt_name[1], proc {subject_alt_name && subject_alt_name != cr.fetch_subject_alt_name[1]}]
  list << [:min_validity, min_validity, time_left, proc { time_left < min_validity }]

  require_action = false
  list.each do |e|
    if e[3].call
      Chef::Log.debug e
      Chef::Log.info "Changes on #{e[0]} required new certificate"
      Chef::Log.info "Desired value '#{e[1]}' current value '#{e[2]}'"
      require_action = true
    end
  end 
   
  return unless require_action 

  converge_by "Regenerating certs" do  
      action_delete
      action_create
  end
end

action :delete do
  cert_dst = @new_resource.cert_dst
  key_dst = @new_resource.key_dst
  return unless ::File.exists? cert_dst or ::File.exists? key_dst
  converge_by "Deleting #{cert_dst} and #{key_dst}" do
    file "#{cert_dst}" do 
      action :delete
    end
   
    file "#{key_dst}" do 
      action :delete
    end
    
    log 'success' do
      message "Deleted '#{cert_dst}' and '#{key_dst}' successfully"
      level :info
    end  
  end
end


require 'openssl'

class CertGen
  DEFAULT_DURATION = 2 * 365 * 24 * 60 * 60 
  DEFAULT_BASIC_CONSTRAINT = 'CA:FALSE'
  DEFAULT_KEY_USAGE = 'keyEncipherment,dataEncipherment,digitalSignature'
  DEFAULT_SUBJECT_ALT_NAME = 'IP:127.0.0.1'

  def initialize(opts={}) 
   [:ca_key, :ca_cert, :subject ].each do |e|
     raise "Option :#{e} must be specified" if opts[e].nil?
   end

    @ca_key = opts[:ca_key]
    @ca_cert = opts[:ca_cert]
    @subject = opts[:subject]
    @subject_alt_name = opts[:subject_alt_name]
    @basic_constraints = opts[:basic_constraints]
    @key_usage = opts[:key_usage]
    @duration = opts[:duration]
  end
  
   def generate 
     result = {
       cert: nil,
       key: nil 
     }

     cert = gen_cert ({
       subject: @subject,
       ca_cert: OpenSSL::X509::Certificate.new(@ca_cert),
       ca_key: OpenSSL::PKey::RSA.new(@ca_key),
       key_usage: @key_usage,
       basic_constraints: @basic_constraints,
       subject_alt_name: @subject_alt_name
     })

     result[:cert] = cert[:cert].to_pem
     result[:key] = cert[:key].to_pem
     result
   end

   private   
   def gen_key 
     OpenSSL::PKey::RSA.new 2048           
   end 
  
   def gen_ca(opts={})
     result = {
       cert: nil,
       key: nil
     }
     subject = opts[:subject]
     key = gen_key
     public_key = key.public_key
     cert = OpenSSL::X509::Certificate.new 
     cert.subject = cert.issuer = OpenSSL::X509::Name.parse(subject)
     cert.not_before = Time.now
     cert.not_after = Time.now + 10 * 365 * 24 * 60 * 60
     cert.public_key = public_key
     cert.serial = 0x0
     cert.version = 2
     
     ef = OpenSSL::X509::ExtensionFactory.new
     ef.subject_certificate = cert
     ef.issuer_certificate = cert
     cert.extensions = [
       ef.create_extension("basicConstraints","CA:TRUE", true),
       ef.create_extension("subjectKeyIdentifier", "hash")
     ]

     cert.add_extension ef.create_extension(
       "authorityKeyIdentifier", "keyid:always,issuer:always"
     )

     cert.sign key, OpenSSL::Digest::SHA1.new
     result[:cert] = cert
     result[:key] = key
     result
   end
   
   def gen_csr (opts={})
     subject = opts[:subject]
     key = opts[:key]
     csr = OpenSSL::X509::Request.new
     csr.version = 0
     csr.public_key = key.public_key
     csr.subject = OpenSSL::X509::Name.parse(subject)
     csr.sign key, OpenSSL::Digest::SHA1.new
     csr 
   end

   def gen_cert(opts={})
     result = {
       key: nil,
       cert: nil
     }
     subject = opts[:subject]
     ca_cert = opts[:ca_cert]
     ca_key = opts[:ca_key]
     subject_alt_name = opts[:subject_alt_name] || DEFAULT_SUBJECT_ALT_NAME
     basic_constraints = opts[:basic_constraints] || DEFAULT_BASIC_CONSTRAINT
     key_usage = opts[:key_usage] || DEFAULT_KEY_USAGE

     key = gen_key
     csr = gen_csr subject: subject, key: key
     
     cert = OpenSSL::X509::Certificate.new
     cert.serial = 0
     cert.version = 2
     cert.not_before = Time.now
     cert.not_after = Time.now + DEFAULT_DURATION
     cert.subject = csr.subject
     cert.public_key = csr.public_key
     cert.issuer = ca_cert.subject
     ef = OpenSSL::X509::ExtensionFactory.new
     ef.subject_certificate = cert
     ef.issuer_certificate = ca_cert

     cert.add_extension ef.create_extension('basicConstraints', basic_constraints) 
     cert.add_extension ef.create_extension('keyUsage',key_usage) 
     cert.add_extension ef.create_extension('subjectAltName',subject_alt_name) 
     cert.add_extension    ef.create_extension('subjectKeyIdentifier', 'hash')

     cert.sign ca_key, OpenSSL::Digest::SHA1.new
     result[:key] = key
     result[:cert] = cert
     result
   end
end

def cert_gen_usage_example
  require 'fileutils'
  out = '/tmp/ssl_fun'
  FileUtils.mkdir_p out   
  cg = CertGen.new({
    ca_key: File.read("#{out}/ca-key.pem"),
    ca_cert: File.read("#{out}/ca-cert.pem"),
    subject: "CN=Tiago"
  })
  cert = cg.generate
  File.open("#{out}/node-cert.pem",'w+'){|f| f.write cert[:cert]}
  File.open("#{out}/node-key.pem",'w+'){|f| f.write cert[:key]}
end

class CertReader 
  def initialize (cert)
    @cert = OpenSSL::X509::Certificate.new cert
  end

  def fetch_not_after
    @cert.not_after
  end
   
  def fetch_subject 
    @cert.subject.to_s
  end

  def fetch_basic_constraints
    fetch_extension 'basicConstraints'
  end

  def fetch_subject_alt_name
    fetch_extension 'subjectAltName'
  end

  def fetch_key_usage
    fetch_extension 'keyUsage'
  end
  private 
  def fetch_extension(extension_name)
    bc = @cert.extensions.find do |e|
      e.to_a[0] == extension_name
    end
    bc.to_a if bc
  end
end

def cert_reader_usage_example
  cr = CertReader.new(File.read '/tmp/ssl_fun/node-cert.pem')
  p cr.fetch_basic_constraints
  p cr.fetch_subject_alt_name
  p cr.fetch_key_usage
  p cr.fetch_subject
  p cr.fetch_not_after
end
