class Subspace::Commands::MaintenanceMode < Subspace::Commands::Base
  PASS_THROUGH_PARAMS = ["private-key", "limit"]

  def initialize(args, options)
    @hosts = args.first
    @options = options
    run
  end

  def run
    on_off = @options.__hash__[:on] ? "on" : "off"
    ansible_options = ["--diff", "-e maintenance_hosts=#{@hosts}", "--tags=maintenance_#{on_off}"]
    ansible_options = ansible_options | pass_through_params
    ansible_command "ansible-playbook",  File.join(File.dirname(__FILE__), "../../../ansible/playbooks/maintenance_mode.yml"), *ansible_options
  end
end
