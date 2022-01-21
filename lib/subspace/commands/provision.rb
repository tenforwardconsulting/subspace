class Subspace::Commands::Provision < Subspace::Commands::Base
  PASS_THROUGH_PARAMS = ["tags", "start-at-task", "private-key", "limit"]

  def initialize(args, options)
    @environment = args.first
    @options = options
    set_subspace_version
    run
  end

  def run
    ansible_playbook "#{@environment}.yml", *pass_through_params
  end
end
