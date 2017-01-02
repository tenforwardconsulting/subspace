class Subspace::Configuration
  attr_accessor :project_name
  attr_reader :vars

  def initialize
    @host_config = {}
    @role_config = {}
    @vars = OpenStruct.new
  end

  def host(name, options)
    @host_config[name] = options
  end

  def role(name, options={}, &block)
    @role_config[name] = options
    yield vars
  end

end
