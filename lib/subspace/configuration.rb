require "ostruct"
class Subspace::Configuration
  attr_accessor :project_name
  attr_reader :vars, :host_config, :group_config

  def initialize
    @host_config = {}
    @group_config = {}
    @vars = OpenStruct.new
  end

  def host(name, options)
    @host_config[name] = options
  end

  def hosts
    @host_config.keys
  end

  def groups
    @group_config.keys
  end

  def group(name, hosts: [], vars: {})
    group_config(name).hosts += hosts
    group_config(name).vars.merge!(vars)
  end

  def role(name, groups: [], vars: {})
    groups.each do |group|
      group_config(group).roles.push(name.to_sym)
      vars.each do |k,v|
        if group_config(group).vars[k]
          put "Warning, variable '#{k}' already set for group '#{group}'"
        end
        group_config(group).vars[k] = v
      end
    end
  end

  def binding_for(host: nil, group: nil)
    config = @vars.dup
    if host
      @host_config[host].each do |k,v|
        config[k] = v
      end
    end
    b = binding
    b.local_variable_set(:config, config)
    b
  end

  private

  def group_config(group)
    @group_config[group.to_sym] ||= GroupConfig.new(group)
  end

  class GroupConfig
    attr_reader :name, :vars
    attr_accessor :hosts, :roles
    def initialize(name)
      @name = name.to_sym
      @hosts = []
      @roles = []
      @vars = OpenStruct.new
    end
  end
end
