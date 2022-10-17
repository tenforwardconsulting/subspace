require 'yaml'
require 'subspace/inventory'
class Subspace::Commands::Ssh < Subspace::Commands::Base
  PASS_THROUGH_PARAMS = ["i"]

  def initialize(args, options)
    @host = args.first
    @user = options.user
    @options = options
    run
  end

  def run
    if !inventory.hosts[@host]
      say "No host '#{@host}' found. "
      all_hosts = inventory.hosts.keys
      say (["Available hosts:"] + all_hosts).join("\n\t")
      return
    end
    host_vars = inventory.hosts[@host].vars
    if host_vars.key?('ansible_ssh_user')
      say "Supposed to be ansible_user not ansible_ssh_user"
    end
    user = host_vars["ansible_user"]
    host = host_vars["ansible_host"]
    port = host_vars["ansible_port"] || 22
    pem = host_vars["ansible_ssh_private_key_file"]
    pem_cmd = "-i config/subspace/#{pem}" if pem
    cmd = "ssh #{user}@#{host} -p #{port} #{pem_cmd} #{pass_through_params.join(" ")}"
    say "> #{cmd} \n"
    exec cmd
  end
end
