require 'yaml'
class Subspace::Commands::Ssh < Subspace::Commands::Base
  def initialize(args, options)
    @host = args.first
    @user = options.user
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
    cmd = "ssh #{user}@#{host}"
    say cmd
    exec cmd
  end
end
