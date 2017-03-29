class Subspace::Commands::Configure < Subspace::Commands::Base
  def initialize(args, options)
    require_configuration
    run
  end

  def run
    Subspace.config.hosts.each do |host|
      update_host_configuration(host)
    end
    Subspace.config.groups.each do |group|
      update_group_configuration(group)
    end
  end

  private

  def update_host_configuration(host)
    say "Generating config/provisiong/host_vars/#{host}"
    template "host_vars/template", "host_vars/#{host}", Subspace.config.binding_for(host: host)
  end

  def update_group_configuration(group)
    say "Generating config/provisiong/group_vars/#{group}"
    template "group_vars/template", "group_vars/#{group}", Subspace.config.binding_for(group: group)
  end

  def update_ansible_cfg
    template "ansible.cfg"
  end

end
