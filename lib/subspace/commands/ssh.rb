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
    inventory = Subspace::Inventory.read("config/subspace/inventory.yml")
    if !inventory.hosts[@host]
      say "No host '#{@host}' found. "
      all_hosts = inventory.hosts.keys
      say (["Available hosts:"] + all_hosts).join("\n\t")
      return
    end
    host_vars = inventory.hosts[@host].vars
    user = host_vars["ansible_ssh_user"]
    host = host_vars["ansible_ssh_host"]
    port = host_vars["ansible_ssh_port"] || 22
    pem = host_vars["ansible_ssh_private_key_file"] || 'subspace.pem'
    cmd = "ssh #{user}@#{host} -p #{port} -i config/subspace/#{pem} #{pass_through_params.join(" ")}"
    say "> #{cmd} \n"
    exec cmd
  end
end
