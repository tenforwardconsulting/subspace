class Subspace::Commands::Provision < Subspace::Commands::Base
  PASS_THROUGH_PARAMS = ["tags", "start-at-task", "private-key", "limit"]

  def initialize(args, options)
    @environment = args.first
    @options = options
    set_subspace_version
    run
  end

  def run
    ansible_options = ["--diff"]
    ansible_options = ansible_options | pass_through_params
    ansible_command "ansible-playbook", "#{@environment}.yml", *ansible_options
  end
end
