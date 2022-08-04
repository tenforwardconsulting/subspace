require 'yaml'
module Subspace
  class Inventory
    attr_accessor :group_vars, :hosts, :global_vars, :path
    def initialize
      @hosts = {}
      @group_vars = {}
      @global_vars = {}
    end

    # Find all the hosts in the host/group or exit
    def find_hosts!(host_spec)
      if self.groups[host_spec]
        return self.groups[host_spec].host_list.map { |m| self.hosts[m] }
      elsif self.hosts[host_spec]
        return [self.hosts[host_spec]]
      else
        say "No inventory matching: '#{host_spec}' found. "
        say (["Available hosts:"] + self.hosts.keys).join("\n\t")
        say (["Available groups:"] + self.groups.keys).join("\n\t")
        exit
      end
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
          inventory.hosts[host].group_list.push name
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
      inventory_json["hostnames"].each_with_index do |host, i|
        if hosts[host]
          old_ip = hosts[host].vars["ansible_host"]
          new_ip = inventory_json["ip_addresses"][i]
          if old_ip != new_ip
            say "  * Host '#{host}' IP address changed! You may need to update the inventory! (#{old_ip} => #{new_ip})"
          end
          next
        end
        hosts[host] = Host.new(host)
        hosts[host].vars["ansible_host"] = inventory_json["ip_addresses"][i]
        hosts[host].vars["ansible_user"] = inventory_json["users"][i]
        hosts[host].vars["hostname"] = host
        hosts[host].group_list = inventory_json["groups"][i].split(/\s/)
      end
    end

    def to_yml
      all_groups = {}
      all_hosts = {}
      @hosts.each do |name, host|
        all_hosts[host.name] = host.vars.empty? ? nil : host.vars.transform_keys(&:to_s)
        host.group_list.each do |group|
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

    def groups
      @groups ||= begin
        all_groups = {"all" => Group.new("all", vars: {}, host_list: hosts.keys) }
        @hosts.each do |name, host|
          host.group_list.each do |group|
            all_groups[group] ||= Group.new(group, vars: @group_vars[group])
            all_groups[group].host_list.append(name)
          end
        end
        all_groups
      end
    end

    class Host
      attr_accessor :vars, :group_list, :name

      def initialize(name, vars: {}, group_list: [])
        @name = name
        @vars = vars
        @group_list = group_list
      end
    end

    class Group
      attr_accessor :name, :vars, :host_list
      def initialize(name, vars: {}, host_list: [])
        @name = name
        @vars = vars
        @host_list = host_list
      end
    end
  end
end
