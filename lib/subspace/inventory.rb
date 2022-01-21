require 'yaml'
module Subspace
  class Inventory
    attr_accessor :group_vars, :hosts, :global_vars, :path
    def initialize
      @hosts = {}
      @group_vars = {}
      @global_vars = {}
    end

    def self.read(path)
      inventory = new
      inventory.path = path

      yml = YAML.load(File.read(path)).to_h

      # Run through all hosts
      yml["all"]["hosts"].each do |name, vars|
        inventory.hosts[name] = Host.new(name, vars: vars || {})
      end

      # Run through all children (groups)
      # This does NOT handle sub-groups yet
      yml["all"]["children"].each do |name, group|
        next unless group["hosts"]

        # Each group defines its host membership
        group["hosts"].each do |host, vars|
          inventory.hosts[host] ||= Host.new(host, vars: vars || {})
          inventory.hosts[host].groups.push name
        end

        if group["vars"]
          inventory.group_vars[name] = group["vars"]
        end
      end

      # Capture global variables
      inventory.global_vars = yml["all"]["vars"] || {}

      inventory
    end

    def write(path=nil)
      File.write(@path || path, self.to_yml)
    end

    def merge(inventory_json)
      inventory_json["inventory"]["value"]["hostnames"].each_with_index do |host, i|
        hosts[host] ||= Host.new(host)
        hosts[host].vars["ansible_host"] = inventory_json["inventory"]["value"]["ip_addresses"][i]
        hosts[host].vars["ansible_user"] = inventory_json["inventory"]["value"]["user"][i]
        hosts[host].vars["hostname"] = host
        hosts[host].groups = inventory_json["inventory"]["value"]["groups"][i].split(/\s/)
      end
    end

    def to_yml
      all_hosts = {}
      all_groups = {}
      @hosts.each do |name, host|
        all_hosts[host.name] = host.vars.empty? ? nil : host.vars.transform_keys(&:to_s)
        host.groups.each do |group|
          all_groups[group] ||= { "hosts" => {}}
          all_groups[group]["hosts"][host.name] = nil
        end

      end

      @group_vars.each do |group, vars|
        all_groups[group] ||= {}
        if !vars.empty?
          all_groups[group]["vars"] = vars.transform_keys(&:to_s)
        end
      end

      yml = {
        "all" => {
          "hosts" => all_hosts,
          "children" => all_groups.empty? ? nil : all_groups
        }
      }

      if !@global_vars.empty?
        yml["all"]["vars"] = @global_vars.transform_keys(&:to_s)
      end

      YAML.dump(yml)
    end

    class Host
      attr_accessor :vars, :groups, :name

      def initialize(name, vars: {}, groups: [])
        @name = name
        @vars = vars
        @groups = groups
      end
    end

    class Group
      attr_accessor :name, :vars
      def initialize(name, vars: {})
        @name = name
        @vars = vars
      end
    end
  end
end