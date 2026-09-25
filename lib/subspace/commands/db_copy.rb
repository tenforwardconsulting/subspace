require 'subspace/upgrade'
class Subspace::Commands::DbCopy < Subspace::Commands::Base
  def initialize(args, options, overwrite: false, check_only: false)
    @source = args[0] || options.from
    @destination = args[1] || options.to
    @options = options
    @overwrite = overwrite
    @check_only = check_only
    run
  end

  def run
    if @source.nil? || @destination.nil?
      say "Usage: subspace db_copy --from production-app1 --to production-app2"
      exit 1
    end
    inventory.find_hosts! @source
    inventory.find_hosts! @destination

    unless instance_ssh_available?
      abort <<~EOS
        The instances in #{env} cannot ssh to each other.  Set allow_instance_ssh = true in
        config/subspace/terraform/#{env}/main.tf and apply it first, or use
        `subspace upgrade #{env} --copy-db`, which opens the path for the duration of the copy.
      EOS
    end

    if @check_only
      say "Checking that #{@source} can ssh to #{@destination}."
    else
      say "Copying the #{env} database from #{@source} to #{@destination}."
    end
    extra_vars = ["db_copy_source=#{@source}",
                  "db_copy_destination=#{@destination}",
                  "db_copy_force=#{!!@options.force}",
                  "db_copy_overwrite=#{@overwrite}",
                  "db_copy_destination_ip=#{destination_private_ip}"]

    # Agent forwarding is how the source host reaches the destination without a
    # server-to-server key being created, and mitogen does not forward the agent.  The
    # separate control path keeps ssh from reusing a connection an earlier playbook
    # opened without forwarding.
    with_mitogen_disabled do
      with_key_in_agent do
        unless ansible_playbook(File.join(playbook_dir, "db_copy.yml"),
          *(@check_only ? ["--tags", "db_copy_check"] : []),
          *extra_vars.flat_map { |var| ["-e", var] },
          "-e", "ansible_ssh_extra_args=-o ForwardAgent=yes",
          "-e", "ansible_control_path=/tmp/subspace-dbcopy-%%h-%%p-%%r")
          abort "db_copy from #{@source} to #{@destination} failed."
        end
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

  def instance_ssh_available?
    terraform.output("allow_instance_ssh") == true
  end

  def destination_private_ip
    instance = terraform.output("instances").values.find { |i| i["hostname"] == @destination }
    abort "#{@destination} is not in #{env}'s terraform output." if instance.nil?
    instance.fetch "private_ip"
  end

  # Ansible hands subspace.pem to ssh with -i, so it is not in the agent being forwarded.
  def with_key_in_agent
    pem = "config/subspace/subspace.pem"
    unless system("ssh-add", "-t", "3600", pem)
      abort "Could not add #{pem} to your ssh agent, which the copy forwards to #{@source}.  Is ssh-agent running?"
    end
    yield
  ensure
    system "ssh-add", "-d", pem
  end

  def with_mitogen_disabled
    was = ENV["DISABLE_MITOGEN"]
    ENV["DISABLE_MITOGEN"] = "1"
    yield
  ensure
    ENV["DISABLE_MITOGEN"] = was
  end
end
