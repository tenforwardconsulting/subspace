require 'yaml'
class Subspace::Commands::Ssh < Subspace::Commands::Base
  def initialize(args, options)
    @host = args.first
    run
  end

  def run
    host_vars = YAML.load_file("config/provision/host_vars/#{@host}")
    cmd = "ssh #{host_vars["ansible_ssh_user"]}@#{host_vars["ansible_ssh_host"]}"
    say cmd
    exec cmd
  end

  private

  def update_ansible_cfg
    template "ansible.cfg"
  end

end
