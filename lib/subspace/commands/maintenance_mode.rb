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
    PASS_THROUGH_PARAMS.each do |param_name|
      x = param_name.split('-')[1..-1].map(&:upcase).join('_')
      hash_key = (param_name.gsub('-', '_') + (x == '' ? '' : "_#{x}")).to_sym
      value = @options.__hash__[hash_key]
      if value
        ansible_options += ["--#{param_name}", value]
      end
    end
    ansible_command "ansible-playbook", "maintenance_mode.yml", *ansible_options
  end
end
