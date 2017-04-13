class Subspace::Commands::Provision < Subspace::Commands::Base
  def initialize(args, options)
    @environment = args.first
    run
  end

  def run
    ansible_command "ansible-playbook", "#{@environment}.yml", "--diff"
  end
end
