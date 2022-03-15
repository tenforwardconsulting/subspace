require 'yaml'
require 'subspace/inventory'
class Subspace::Commands::Exec < Subspace::Commands::Base
  PASS_THROUGH_PARAMS = ["i"]

  def initialize(args, options)
    @host_spec = args[0]
    @command = args[1]
    @user = options.user
    @options = options
    run
  end

  def run
    hosts = inventory.find_hosts!(@host_spec)

    say "> Running `#{@command}` on #{hosts.join ','}"
    ansible_command "ansible", @host_spec, "-m", "command", "-a", @command
  end
end
