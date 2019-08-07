class Subspace::Commands::Maintain < Subspace::Commands::Base
  PASS_THROUGH_PARAMS = ["private-key", "limit"]

  def initialize(args, options)
    @environment = args.first
    @options = options
    run
  end

  def run
    ansible_options = ["--diff", "--tags=maintenance"]
    PASS_THROUGH_PARAMS.each do |param_name|
      x = param_name.split('-')[1..-1].map(&:upcase).join('_')
      hash_key = (param_name.gsub('-', '_') + (x == '' ? '' : "_#{x}")).to_sym
      value = @options.__hash__[hash_key]
      if value
        ansible_options += ["--#{param_name}", value]
      end
    end
    ansible_command "ansible-playbook", "#{@environment}.yml", *ansible_options
  end
end
