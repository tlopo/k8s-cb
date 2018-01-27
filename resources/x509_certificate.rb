
actions :create, :delete, :update
default_action :create

attribute :ca_cert, kind_of: String, required: true
attribute :ca_key, kind_of: String, required: true
attribute :cert_dst, kind_of: String, required: true
attribute :key_dst, kind_of: String, required: true
attribute :subject, kind_of: String, required: true
attribute :subject_alt_name, kind_of: String, required: false
attribute :basic_constraints, kind_of: String, required: false
attribute :key_usage, kind_of: String, required: false
attribute :min_validity, kind_of: Fixnum, required: false
