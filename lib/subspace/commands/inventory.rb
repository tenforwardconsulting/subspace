class Subspace::Commands::Inventory < Subspace::Commands::Base

  def initialize(args, options)
    command = args.first
    @env = options.env
    case command
    when "capistrano"
      capistrano_deployrb
    when "list"
      list_inventory
    when "keyscan"
      keyscan_inventory
    else
      say "Unknown or missing command to inventory: #{command}"
      say "try subspace inventory [list, capistrano]"
    end
  end

  def list_inventory
    inventory.find_hosts!(@env || "all").each do |host|
      puts "#{host.name}\t#{host.vars["ansible_host"]}\t(#{host.group_list.join ','})"
    end
  end

  def keyscan_inventory
    inventory.find_hosts!(@env || "all").each do |host|
      ip = host.vars["ansible_host"]
      system %Q(ssh-keygen -R #{ip})
      system %Q(ssh-keyscan -Ht ed25519 #{ip} >> "$HOME/.ssh/known_hosts")
    end
  end

  def capistrano_deployrb
    if @env.nil?
      puts "Please provide an environment e.g: subspace inventory capistrano --env production"
      exit
    end

    say "# config/deploy/#{@env}.rb"
    say "# Generated by Subspace"
    inventory.find_hosts!(@env).each do |host|
      host = inventory.hosts[host.name]
      db_role = false
      roles = host.group_list.map do |group_name|
        if group_name =~ /web/
          ["web", "app"]
        elsif group_name =~ /worker/
          ["app", db_role ? nil : "db"]
        end
      end.compact.uniq
      say "server '#{host.vars["ansible_host"]}', user: 'deploy', roles: %w{#{roles.join(' ')}} # #{host.vars["hostname"]}"
    end
  end
end
