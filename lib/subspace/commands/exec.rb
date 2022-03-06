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
    hosts = []
    if inventory.groups[@host_spec]
      hosts = inventory.groups[@host_spec].host_list
    elsif inventory.hosts[@host_spec]
      hosts = [@host_spec]
    else
      say "No inventory matching: '#{@host_spec}' found. "
      say (["Available hosts:"] + inventory.hosts.keys).join("\n\t")
      say (["Available groups:"] + inventory.groups.keys).join("\n\t")
      exit
    end
    say "> Running `#{@command}` on #{hosts.join ','}"
    ansible_command "ansible", @host_spec, "-m", "command", "-a", @command
  end
end
