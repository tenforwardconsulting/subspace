require 'subspace/upgrade'
class Subspace::Commands::DbCopy < Subspace::Commands::Base
  def initialize(args, options)
    @source = args[0] || options.from
    @destination = args[1] || options.to
    @options = options
    run
  end

  def run
    if @source.nil? || @destination.nil?
      say "Usage: subspace db_copy --from production-app1 --to production-app2"
      exit 1
    end
    inventory.find_hosts! @source
    inventory.find_hosts! @destination

    say "Copying the #{env} database from #{@source} to #{@destination}."
    extra_vars = ["db_copy_source=#{@source}",
                  "db_copy_destination=#{@destination}",
                  "db_copy_force=#{!!@options.force}",
                  "db_copy_via_local=#{via_local?}",
                  "db_copy_destination_ip=#{via_local? ? "" : destination_private_ip}"]

    # Agent forwarding is how the source host reaches the destination without a
    # server-to-server key being created, and mitogen does not forward the agent.
    with_mitogen_disabled do
      unless ansible_playbook(File.join(playbook_dir, "db_copy.yml"),
                              *extra_vars.flat_map { |var| ["-e", var] },
                              "-e", "ansible_ssh_extra_args=-o ForwardAgent=yes")
        abort "db_copy from #{@source} to #{@destination} failed."
      end
    end
  end

  private

  def env
    @env ||= begin
      groups = inventory.hosts.fetch(@destination).group_list
      groups.find { |group| Dir.exist? File.join("config/subspace/terraform", group) } ||
        abort("Could not tell which terraform environment #{@destination} belongs to (groups: #{groups.join ", "}).")
    end
  end

  def terraform
    @terraform ||= Subspace::Upgrade::Terraform.new env
  end

  def via_local?
    return @via_local unless @via_local.nil?

    @via_local = if @options.via_local
      true
    elsif !instance_ssh_available?
      say "The instances cannot ssh to each other, so the dump goes through this machine."
      say "That is slower for a large database.  `subspace upgrade #{env} --cutover` opens the"
      say "path between them for the duration of the copy."
      true
    else
      say "Streaming directly between the instances over the private network."
      false
    end
  end

  def instance_ssh_available?
    terraform.output("allow_instance_ssh") == true
  rescue JSON::ParserError
    false
  end

  def destination_private_ip
    instance = terraform.output("instances").values.find { |i| i["hostname"] == @destination }
    abort "#{@destination} is not in #{env}'s terraform output." if instance.nil?
    instance.fetch "private_ip"
  end

  def with_mitogen_disabled
    was = ENV["DISABLE_MITOGEN"]
    ENV["DISABLE_MITOGEN"] = "1"
    yield
  ensure
    ENV["DISABLE_MITOGEN"] = was
  end
end
