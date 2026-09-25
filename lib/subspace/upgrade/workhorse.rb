require 'digest'
module Subspace
  module Upgrade
    # One server, postgres and redis on the box, an elastic IP in front.  The upgrade
    # stands a second instance slot up beside the first, copies the database across in a
    # maintenance window, and moves the elastic IP.
    class Workhorse < Base
      TEMPLATE = "workhorse"
      KEYED_RESOURCE = "aws_instance.single"
      REQUIRED_MODULE_VARIABLES = %w[instances active_instance allow_instance_ssh]
      REQUIRED_ROOT_OUTPUTS = %w[inventory instances active_instance allow_instance_ssh]
      STATE_REQUIRES = ["aws_instance.single"]
      STATE_FORBIDS = ["aws_lb", "aws_db_instance"]

      def prepare
        check!
        state.require_phase! "initialized"
        assert_clean_git_tree!

        from_slot = config.active_instance
        to_slot = next_slot
        to_hostname = next_hostname
        say "Upgrading #{template} #{env}: slot #{from_slot} (#{from_hostname}) => slot #{to_slot} (#{to_hostname})"

        confirm_database_backup! from_hostname

        state["from_slot"] = from_slot
        state["to_slot"] = to_slot
        state["from_hostname"] = from_hostname
        state["to_hostname"] = to_hostname
        state["from_ami"] = TerraformConfig.unquote config.instances[from_slot]["ami"]
        state["to_ami"] = target_ami
        state["ubuntu_release"] = ubuntu_release
        state.save

        config.add_instance to_slot,
                            "hostname" => %("#{to_hostname}"),
                            "ami" => %("#{state["to_ami"]}"),
                            "instance_type" => config.instances[from_slot]["instance_type"],
                            "volume_size" => config.instances[from_slot]["volume_size"]

        apply! address(%(aws_instance.single["#{to_slot}"])) => ["create"]

        update_inventory!
        add_to_group! to_hostname, "upgrade"

        Subspace::Commands::Bootstrap.new [to_hostname], options
        copy_letsencrypt!
        provision! to_hostname
        write_capistrano_stage!

        state.advance! "prepared"
        say next_step_for "prepared"
      end

      # Opens the maintenance window and moves the data, but leaves the elastic IP where it
      # is.  The new server is then fully loaded and reachable on its own address, so it can
      # be verified against real data while users still see the maintenance page.
      def copy_db
        check!
        state.require_phase! "prepared"
        verify_deployed! state["to_hostname"]

        say "This opens #{env}'s maintenance window: #{state["from_hostname"]} stops serving now"
        say "and stays down until `--cutover` or `--abort`.  The elastic IP does not move yet."
        abort "Aborted." unless ask("Continue? [no] ").downcase.start_with? "y"

        # Recorded before the window opens, not after the phase completes, so an interrupted
        # --copy-db still tells --abort that the old server needs starting again.
        state["window_open"] = true
        state.save

        maintenance_mode! :on, state["from_hostname"]
        verify_maintenance_page! state["from_hostname"]
        stop_application! state["from_hostname"]

        begin
          open_instance_ssh!
          db_copy! state["from_hostname"], state["to_hostname"]
          state.advance! "copied"
        ensure
          close_instance_ssh
        end

        say next_step_for "copied"
      end

      # Moves the elastic IP.  Everything that touches data already happened in --copy-db.
      def cutover
        check!
        state.require_phase! "copied"

        unless serves_domain? to_public_ip
          abort "#{state["to_hostname"]} is not serving the site on its own address.  Nothing has moved yet."
        end

        say "This points #{env}'s elastic IP at #{state["to_hostname"]} and ends the maintenance window."
        say "After this there is no --abort: #{state["to_hostname"]} holds the only current data."
        abort "Aborted." unless ask("Continue? [no] ").downcase.start_with? "y"

        flip_active_instance! state["to_slot"]

        # Recorded before the checks below: the elastic IP has moved, so the new server is
        # live and `--abort` must never be able to destroy it.
        state["window_open"] = false
        state.advance! "cutover"

        health_check!
        assert_not_in_maintenance_mode! state["to_hostname"]

        say next_step_for "cutover"
      end

      # Undo everything before the elastic IP moved: destroy the new slot and, if the
      # maintenance window is open, put the old server back into service.  The old server
      # still holds the data it always had -- nothing has written to it since --copy-db
      # stopped it.
      def abort_upgrade
        check!
        state.require_phase! "prepared", "copied"
        say "This destroys #{state["to_hostname"]} (slot #{state["to_slot"]}) and leaves #{env} on #{state["from_hostname"]}."
        abort "Aborted." unless ask("Type the environment name to confirm: ").strip == env

        if state["window_open"]
          start_application! state["from_hostname"]
          maintenance_mode! :off, state["from_hostname"]
        end

        config.remove_instance state["to_slot"]
        apply! address(%(aws_instance.single["#{state["to_slot"]}"])) => ["delete"]

        remove_host! state["to_hostname"]
        FileUtils.rm_f capistrano_stage_path
        state.destroy
        say "Aborted the upgrade.  Commit the config diff."
      end

      def finalize
        check!
        state.require_phase! "cutover"

        say "This permanently destroys #{state["from_hostname"]} (slot #{state["from_slot"]}) and its database."
        say "After this there is no way back, only the dump this step takes and the backup you took"
        say "yourself at --prepare."
        abort "Aborted." unless ask("Type #{state["from_hostname"]} to confirm: ").strip == state["from_hostname"]

        backup_database! state["from_hostname"]

        config.remove_instance state["from_slot"]
        apply! address(%(aws_instance.single["#{state["from_slot"]}"])) => ["delete"]

        remove_host! state["from_hostname"]
        remove_from_group! state["to_hostname"], "upgrade"
        FileUtils.rm_f capistrano_stage_path

        state.advance! "finalized"
        say "#{env} is running on #{state["to_hostname"]} (#{state["to_ami"]}).  Commit the config diff."
      end

      private

      def from_hostname
        config.hostname_for config.active_instance
      end

      def next_slot
        (config.instances.keys.map(&:to_i).max + 1).to_s
      end

      # dev-app1 => dev-app2.  The slot key and the hostname number are independent, so
      # derive the name from the active host rather than from the key.
      def next_hostname
        hostname = from_hostname.sub(/(\d+)\z/) { $1.to_i + 1 }
        taken = config.instances.values.map { |attributes| TerraformConfig.unquote attributes["hostname"] }
        if hostname == from_hostname || taken.include?(hostname)
          abort "Could not derive a free hostname from '#{from_hostname}'.  Rename it to end in a number."
        end
        hostname
      end

      def ubuntu_release
        options.ubuntu_release || Subspace::Ami::DEFAULT_RELEASE
      end

      def target_ami
        options.ami || Subspace::Ami.latest(release: ubuntu_release, profile: aws_profile)
      end

      # ------------------------------------------------------------- data

      # Subspace does not take this one.  A dump nobody has restored is not a backup, and
      # verifying it means loading it somewhere only you have.
      def confirm_database_backup!(hostname)
        say "Back #{hostname}'s database up before anything else happens, and verify the dump by"
        say "restoring it locally and checking that the data is really in there.  It is the only"
        say "artifact that survives every possible mistake in the rest of this process."
        abort "Aborted." unless ask("Have you done that? [no] ").downcase.start_with? "y"
      end

      def backup_database!(hostname)
        FileUtils.mkdir_p "tmp/subspace"
        path = File.join "tmp/subspace", "#{env}-#{hostname}-#{Time.now.utc.strftime "%Y%m%dT%H%M%SZ"}.dump"
        say "Backing #{hostname}'s database up to #{path} before anything else happens."
        playbook_or_abort "db_dump", hostname, "db_dump_dest=#{File.expand_path path}"

        unless File.exist?(path) && File.size(path) > 0
          abort "#{path} is missing or empty.  Refusing to continue without a database backup."
        end

        state["backup_path"] = path
        state["backup_bytes"] = File.size path
        state["backup_sha256"] = Digest::SHA256.file(path).hexdigest
        state.save
        say "#{path} (#{state["backup_bytes"]} bytes, sha256 #{state["backup_sha256"]})"
      end

      def db_copy!(source, destination)
        Subspace::Commands::DbCopy.new [source, destination], options
      end

      # --------------------------------------------------------- application

      def provision!(hostname)
        say "Provisioning #{hostname}"
        set_subspace_version
        unless ansible_playbook("#{env}.yml", "--limit", hostname)
          abort "Provisioning #{hostname} failed."
        end
      end

      def verify_deployed!(hostname)
        unless playbook("upgrade_verify", hostname, "upgrade_host=#{hostname}")
          abort "#{hostname} is not ready to take traffic.  Deploy to it and verify it first."
        end
      end

      def maintenance_mode!(on_or_off, hostname)
        say "Maintenance mode #{on_or_off} for #{hostname}"
        # Always limited: the new host shares the <env>_web group, so an unlimited call
        # would take down the server we are cutting over to.
        unless ansible_command("ansible-playbook", File.join(playbook_dir, "maintenance_mode.yml"),
                               "--diff", "-e", "maintenance_hosts=#{hostname}",
                               "--limit", hostname, "--tags=maintenance_#{on_or_off}")
          abort "Could not turn maintenance mode #{on_or_off} on #{hostname}."
        end
      end

      def stop_application!(hostname)
        say "Stopping puma and the workers on #{hostname} (a maintenance page does not stop background jobs)"
        playbook_or_abort "upgrade_quiesce", hostname
      end

      def start_application!(hostname)
        say "Starting puma and the workers back up on #{hostname}"
        playbook_or_abort "upgrade_unquiesce", hostname
      end

      def verify_maintenance_page!(hostname)
        say "Checking that #{hostname} is serving the maintenance page"
        playbook_or_abort "upgrade_verify_maintenance", hostname
      end

      def assert_not_in_maintenance_mode!(hostname)
        return if playbook "upgrade_verify", hostname, "upgrade_host=#{hostname}"

        abort "#{hostname} is serving traffic but did not pass its post-cutover check."
      end

      def to_public_ip
        terraform.output("instances").fetch(state["to_slot"]).fetch("public_ip")
      end

      # HTTP-01 validation cannot pass while the domain still resolves to the old server, so
      # the new one gets the old one's certificates before it is provisioned.
      def copy_letsencrypt!
        FileUtils.mkdir_p "tmp/subspace"
        archive = File.expand_path File.join("tmp/subspace", "#{env}-letsencrypt.tar.gz")
        say "Copying /etc/letsencrypt from #{state["from_hostname"]} to #{state["to_hostname"]}"
        playbook_or_abort "upgrade_copy_letsencrypt",
                          state["from_hostname"],
                          "letsencrypt_archive=#{archive}",
                          "letsencrypt_destination=#{state["to_hostname"]}",
                          limit: [state["from_hostname"], state["to_hostname"]]
      ensure
        FileUtils.rm_f archive if archive
      end

      # Without an address this goes through DNS, which is what users do.
      def serves_domain?(address = nil)
        say "Checking that #{state["to_hostname"]} serves the site by its domain name#{" at #{address}" if address}"
        playbook "upgrade_verify_tls", state["to_hostname"], "upgrade_host=#{state["to_hostname"]}",
                 *("verify_address=#{address}" if address)
      end

      def health_check!
        return if serves_domain?

        abort <<~EOS
          The site is not being served through the elastic IP, which has already moved, so
          #{state["to_hostname"]} is live and holds the only current copy of the data.  Fix it
          there -- do not move the IP back without dealing with the data by hand first.
        EOS
      end

      # ---------------------------------------------------------- terraform

      def open_instance_ssh!
        config.allow_instance_ssh = true
        apply!({ address("aws_security_group.instance_ssh[0]") => ["create"] }
                 .merge(slot_addresses("update")))
      end

      def flip_active_instance!(slot)
        config.active_instance = slot
        apply! address("aws_eip_association.eip_assoc") => %w[create update delete]
        update_inventory!
      end

      # ---------------------------------------------------------- capistrano

      def capistrano_stage_path
        "config/deploy/#{env}_upgrade.rb"
      end

      def write_capistrano_stage!
        Subspace::Commands::Inventory.write_capistrano_stage inventory,
                                                             group: "upgrade",
                                                             rails_env: env,
                                                             path: capistrano_stage_path
        say "Wrote #{capistrano_stage_path}"
      end

      # ------------------------------------------------------------- output

      def playbook_or_abort(name, hostname, *extra_vars, limit: nil)
        return if playbook name, limit || hostname, "upgrade_host=#{hostname}", *extra_vars

        abort "#{name} failed on #{hostname}."
      end

      def next_step_for(phase)
        case phase
        when "initialized" then "subspace upgrade #{env} --prepare"
        when "prepared"
          <<~EOS
            #{state["to_hostname"]} is provisioned at #{inventory.hosts[state["to_hostname"]]&.vars&.dig("ansible_host")} (#{state["to_ami"]}, ubuntu #{state["ubuntu_release"]}).

              1. bundle exec cap #{env}_upgrade deploy
              2. Verify the app: ssh in, check the logs, and browse https://<address>/ (expect a
                 certificate warning), or map your domain to it in /etc/hosts for a faithful test
              3. subspace upgrade #{env} --copy-db

            #{state["from_hostname"]} is still serving all traffic.  Nothing is at risk yet.
          EOS
        when "copied"
          <<~EOS
            #{state["from_hostname"]}'s database is now on #{state["to_hostname"]}, which is running the
            real data on its own address.  #{state["from_hostname"]} is stopped and showing the
            maintenance page, so nothing is writing to either database.

              1. Verify #{state["to_hostname"]} against the real data: https://#{to_public_ip}/ (expect a
                 certificate warning), or map your domain to it in /etc/hosts for a faithful test
              2. subspace upgrade #{env} --cutover   # move the elastic IP, end the window
                 subspace upgrade #{env} --abort     # or back out: destroy #{state["to_hostname"]},
                                                     # restart #{state["from_hostname"]}

            The window is open, so users are seeing the maintenance page until you do one or
            the other.  Both are still safe: nothing has written to #{state["from_hostname"]} since
            it stopped.
          EOS
        when "cutover"
          <<~EOS
            #{state["to_hostname"]} is live on the elastic IP.  #{state["from_hostname"]} is still
            running with the data it had at cutover -- leave it up as long as you like.

              subspace upgrade #{env} --finalize    # destroy #{state["from_hostname"]} for good
          EOS
        when "finalized" then "Nothing.  This upgrade is done -- commit the config diff and delete #{State.path_for env}."
        end
      end

      def migration_instructions
        <<~EOS
          To migrate #{env} (one time, ~5 minutes, no downtime):

            1. Re-vendor the module:
                 subspace upgrade #{env} --revendor       # clones #{MINIMUM_MODULE_REF}, keeps a .bak
            2. In #{config.path} replace
                 instance_ami = "ami-0abc..."
                 instance_type = "t3.medium"
                 instance_hostname = "#{env}-app1"
                 instance_volume_size = 20
               with
                 instances = {
                   "1" = {
                     hostname      = "#{env}-app1"
                     ami           = "ami-0abc..."
                     instance_type = "t3.medium"
                     volume_size   = 20
                   }
                 }
                 active_instance = "1"
            3. Re-export the module's outputs at the root of that same file, so
               `terraform output` can see them:
                 output "inventory"          { value = module.workhorse.inventory }
                 output "instances"          { value = module.workhorse.instances }
                 output "active_instance"    { value = module.workhorse.active_instance }
                 output "allow_instance_ssh" { value = module.workhorse.allow_instance_ssh }
            4. Move the existing instance into its new state address:
                 terraform state mv 'module.workhorse.aws_instance.single' 'module.workhorse.aws_instance.single["1"]'
            5. terraform plan   # MUST show "No changes".  If it shows a replacement, stop
                                # and ask -- do not apply.
        EOS
      end
    end
  end
end
