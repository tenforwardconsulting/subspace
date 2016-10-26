class Subspace::Commands::Provision < Subspace::Commands::Base
  def initialize(args, options)
    @environment = args.first
    run
  end

  def run
    update_ansible_cfg
    ansible_command "ansible-playbook", "#{@environment}.yml"
  end

  private

  def update_ansible_cfg
    template "ansible.cfg"
  end

end
