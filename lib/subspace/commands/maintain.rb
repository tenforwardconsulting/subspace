class Subspace::Commands::Maintain < Subspace::Commands::Base
  PASS_THROUGH_PARAMS = ["private-key", "limit"]

  def initialize(args, options)
    @environment = args.first
    @options = options
    run
  end

  def run
    ansible_options = ["--diff", "--tags=maintenance"]
    ansible_options = ansible_options | pass_through_params
    ansible_command "ansible-playbook", "#{@environment}.yml", *ansible_options
  end
end
