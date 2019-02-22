require 'yaml'
class Subspace::Commands::Ssh < Subspace::Commands::Base
  PASS_THROUGH_PARAMS = ["i"]

  def initialize(args, options)
    @host = args.first
    @user = options.user
    @options = options
    run
  end

  def run
    if !File.exists? "config/provision/host_vars/#{@host}"
      say "No host '#{@host}' found. "
      all_hosts = Dir["config/provision/host_vars/*"].collect {|f| File.basename(f) }
      say (["Available hosts:"] + all_hosts).join("\n\t")
      return
    end
    host_vars = YAML.load_file("config/provision/host_vars/#{@host}")
    user = @user || host_vars["ansible_ssh_user"] || host_vars["ansible_user"]
    host = host_vars["ansible_ssh_host"] || host_vars["ansible_host"]
    port = host_vars["ansible_ssh_port"] || host_vars["ansible_port"] || 22
    ssh_options = []
    PASS_THROUGH_PARAMS.each do |param_name|
      x = param_name.split('-')[1..-1].map(&:upcase).join('_')
      hash_key = (param_name.gsub('-', '_') + (x == '' ? '' : "_#{x}")).to_sym
      value = @options.__hash__[hash_key]
      if value
        ssh_options += ["-#{param_name}", value]
      end
    end
    cmd = "ssh #{user}@#{host} -p #{port} #{ssh_options.join(" ")}"
    say cmd
    exec cmd
  end
end
