class Subspace::Commands::Vars < Subspace::Commands::Base
  def initialize(args, options)
    @environment = args.first
    @action = options.edit ? "edit" : "view"
    run
  end

  def run
    ansible_command "ansible-vault", @action, "vars/#{@environment}.yml"
  end
end
