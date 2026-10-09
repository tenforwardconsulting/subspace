require 'ipaddr'
module Subspace
  module Upgrade
    # Shared machinery for every topology's upgrade.  Subclasses own the actual
    # sequence; nothing in here branches on the template.
    class Base < Subspace::Commands::Base
      MINIMUM_MODULE_REF = "v2.0.0"
      TAILNET = IPAddr.new "100.64.0.0/10"

      # The servers can ssh to each other from --launch until --finalize or --abort, so the
      # applies that open and close that path ride along with ones those phases already run
      # instead of landing in the maintenance window.
      INSTANCE_SSH_PHASES = %w[launching launched prepared copied cutting_over cutover]

      PHASES = {
        check: :check,
        status: :status,
        revendor: :revendor,
        init: :init,
        launch: :launch,
        provision: :provision,
        copy_db: :copy_db,
        cutover: :cutover,
        finalize: :finalize,
        abort: :abort_upgrade,
        close_instance_ssh: :close_instance_ssh,
      }

      attr_reader :env, :options

      def initialize(env, options)
        @env = env
        @options = options
      end

      def template
        self.class::TEMPLATE
      end

      # --------------------------------------------------------------- phases

      def check
        check!
        check_remote_storage!
        check_tailscale!
        say "#{env} is on #{template} #{manifest["ref"]} and ready for `subspace upgrade`."
      end

      def status
        unless State.exist? env
          say "No upgrade in progress for #{env}.  Start one with `subspace upgrade #{env} --init`."
          return
        end

        say "Template:  #{state["template"]}"
        say "Phase:     #{state["phase"]}"
        say "Slots:     #{state["from_slot"]} (#{state["from_ami"]}) => #{state["to_slot"]} (#{state["to_ami"]})" if state["to_slot"]
        say "Backup:    #{state["backup_path"]} (#{state["backup_bytes"]} bytes)" if state["backup_path"]
        state["log"].to_a.each { |entry| say "  #{entry["at"]}  #{entry["phase"]}" }

        if state["window_open"]
          say ""
          say "The maintenance window is OPEN: #{state["from_hostname"]} has puma, the workers and cron"
          say "stopped and is showing the maintenance page."
        end

        if config.allow_instance_ssh
          say ""
          if instance_ssh_phase?
            say "The servers can ssh to each other until --finalize or --abort closes it."
          else
            say "WARNING: allow_instance_ssh is still true.  Instances can ssh to each other."
            say "Close it with `subspace upgrade #{env} --close-instance-ssh`."
          end
        end

        say ""
        say "Next:      #{next_step_for state.phase}"
      end

      def init
        check!
        check_remote_storage!
        check_tailscale!
        if State.exist? env
          abort "#{State.path_for env} already exists.  `--status` to see it, or delete it to start over."
        end

        State.create(env, "template" => template,
          "started_at" => Time.now.utc.iso8601,
          "phase" => "initialized").save
        say "Wrote #{State.path_for env}.  Next: subspace upgrade #{env} --launch"
      end

      def close_instance_ssh
        unless config.allow_instance_ssh
          say "allow_instance_ssh is already false in #{config.path}."
          return
        end

        config.allow_instance_ssh = false
        apply! instance_ssh_change
      end

      def revendor
        mod = Subspace::Commands::Init::TERRAFORM_MODULES.fetch template
        if locally_modified_module?
          abort <<~EOS
            #{module_dir} has been modified locally (its manifest says #{manifest["ref"]}
            but the files do not match that ref).  Re-vendoring would throw those changes away.
            Reconcile them by hand, then re-run with a matching manifest.
          EOS
        end
        update_gitignore!

        backup = "#{module_dir}.bak"
        if Dir.exist? module_dir
          FileUtils.rm_rf backup
          FileUtils.mv module_dir, backup
          say "Moved the old module to #{backup}"
        else
          backup = nil
          FileUtils.mkdir_p File.dirname(module_dir)
        end

        say "Cloning #{mod[:repo]} (#{mod[:ref]}) into #{module_dir}"
        unless system("git", "clone", "--depth", "1", "--branch", mod[:ref], mod[:repo], module_dir)
          if backup
            FileUtils.rm_rf module_dir
            FileUtils.mv backup, module_dir
          end
          abort "Failed to clone #{mod[:repo]}.#{" Restored the previous module." if backup}"
        end
        FileUtils.rm_rf File.join(module_dir, ".git")
        FileUtils.rm_f File.join(module_dir, ".gitmodules")
        ModuleManifest.write module_dir, template: template, repo: mod[:repo], ref: mod[:ref]
        config.module_source = "./modules/#{template}"
        config.save

        say ""
        say migration_instructions
      end

      # --------------------------------------------------------- compatibility

      def check!(clean_plan: true)
        check_module_version!
        check_module_variables!
        check_root_outputs!
        check_state_fingerprint!
        check_instance_ssh!
        check_clean_plan! if clean_plan
      end

      def check_module_version!
        if manifest.nil?
          abort <<~EOS
            Could not tell which terraform module #{env} uses: no #{ModuleManifest::FILENAME}
            in #{module_dir}.

            #{migration_instructions}
          EOS
        end

        if manifest["template"] != template
          abort "#{module_dir} is a #{manifest["template"]} module, not #{template}."
        end

        return if gem_version(manifest["ref"]) >= gem_version(MINIMUM_MODULE_REF)

        abort <<~EOS
          This environment is on terraform-subspace-#{template} #{manifest["ref"]} (needs >= #{MINIMUM_MODULE_REF}).

          #{migration_instructions}
        EOS
      end

      # A manifest can lie about a locally edited module, so check the source itself
      def check_module_variables!
        unless Dir.exist? module_source_dir
          abort "#{module_source_dir} does not exist.  Run `terraform init` in config/subspace/terraform/#{env} first."
        end

        variables = Dir[File.join(module_source_dir, "*.tf")].map { |file| File.read file }.join
        missing = self.class::REQUIRED_MODULE_VARIABLES.reject do |name|
          variables =~ /^variable\s+"?#{name}"?\s/
        end
        return if missing.empty?

        abort <<~EOS
          #{module_source_dir} does not declare #{missing.join(", ")}, so it cannot be upgraded
          even though its manifest claims #{manifest["ref"]}.  It has probably been edited locally.

          #{migration_instructions}
        EOS
      end

      # `terraform output` only resolves root outputs, so a root file that does not
      # re-export the module's fails mid-phase rather than here.
      def check_root_outputs!
        source = File.read config.path
        missing = self.class::REQUIRED_ROOT_OUTPUTS.reject do |name|
          source =~ /^output\s+"#{name}"\s*\{/
        end
        return if missing.empty?

        abort <<~EOS
          #{config.path} does not re-export #{missing.join(", ")} from module.#{config.module_name}.
          The upgrade reads these with `terraform output`, which only sees root outputs.

          Add, for each one:

            output "inventory" {
              value = module.#{config.module_name}.inventory
            }

          #{migration_instructions}
        EOS
      end

      def check_state_fingerprint!
        addresses = terraform.state_list
        if addresses.empty?
          abort "`terraform state list` returned nothing in config/subspace/terraform/#{env}.  Has it been applied?"
        end

        missing = self.class::STATE_REQUIRES.reject { |type| addresses.any? { |a| a.include? type } }
        present = self.class::STATE_FORBIDS.select { |type| addresses.any? { |a| a.include? type } }

        if missing.any? || present.any?
          abort <<~EOS
            #{env} is recorded as a #{template} environment, but its terraform state does not
            look like one.  Refusing to run a #{template} upgrade against it.

              expected but missing:  #{missing.join(", ")}
              present but forbidden: #{present.join(", ")}
          EOS
        end

        return if addresses.any? { |a| a.include? "#{self.class::KEYED_RESOURCE}[" }

        abort <<~EOS
          #{env}'s terraform state still holds an unkeyed #{self.class::KEYED_RESOURCE}.
          Instance slots have to exist before anything can be added beside them.

          #{migration_instructions}
        EOS
      end

      def check_instance_ssh!
        return unless config.allow_instance_ssh
        return if instance_ssh_phase?

        abort <<~EOS
          allow_instance_ssh is true in #{config.path}, which means the instances in #{env}
          can still ssh to each other.  It should only be open from --launch until --finalize.

          Close it:  subspace upgrade #{env} --close-instance-ssh
        EOS
      end

      # EC2 only installs the key pair at launch, so a mismatch leaves the new server
      # unreachable with nothing in the plan to show it.
      def check_subspace_key!
        pem = "config/subspace/subspace.pem"
        authorized = terraform.key_pair_public_key
        abort "No aws_key_pair in #{env}'s terraform state to check #{pem} against." if authorized.nil?

        derived, _, status = Open3.capture3("ssh-keygen", "-y", "-P", "", "-f", pem)
        abort "Could not read a public key from #{pem}." unless status.success?
        return if derived.split[0, 2] == authorized.split[0, 2]

        abort <<~EOS
          The aws_key_pair in #{env}'s terraform state is not the public half of #{pem},
          so a new server would not accept it.

          Regenerate the public key and point #{config.path} at it, then apply:
            ssh-keygen -y -f #{pem} > #{pem}.pub
            subspace_public_key = file("../../subspace.pem.pub")
        EOS
      end

      # Uploads on local disk stay behind on the old server when it is destroyed
      def check_remote_storage!
        environment = File.join "config/environments", "#{env}.rb"
        return unless File.exist?(environment) && File.exist?("config/storage.yml")

        service = File.read(environment)[/^\s*config\.active_storage\.service\s*=\s*[:"']?(\w+)/, 1]
        return unless service && YAML.safe_load(File.read("config/storage.yml"), aliases: true).dig(service, "service") == "Disk"

        abort <<~EOS
          #{environment} stores Active Storage uploads on local disk (:#{service}).  `subspace upgrade`
          does not copy them to the new server.  Move them to S3 first.
        EOS
      end

      # Tailscale addresses belong to the machine, so the inventory and the capistrano stages
      # survive the elastic IP moving to another server.
      def check_tailscale!
        playbook_path = "config/subspace/#{env}.yml"
        unless File.read(playbook_path).match?(/^\s*-\s*tailscale\s*$/)
          abort "#{playbook_path} does not include the tailscale role.  `subspace upgrade` needs every server on the tailnet."
        end

        off_tailnet = inventory.groups.fetch(env).host_list.reject do |name|
          tailnet_address? inventory.hosts.fetch(name).vars["ansible_host"]
        end
        return if off_tailnet.empty?

        abort <<~EOS
          #{off_tailnet.join(", ")} #{off_tailnet.one? ? "is" : "are"} not addressed by tailscale IP in config/subspace/inventory.yml.
          Set ansible_host to each server's `tailscale ip -4`, and point the server lines in
          config/deploy/#{env}.rb at it too, so neither changes when the elastic IP moves.
        EOS
      end

      def tailnet_address?(address)
        TAILNET.include? IPAddr.new(address.to_s)
      rescue IPAddr::InvalidAddressError
        false
      end

      def check_clean_plan!
        status = terraform.plan_exit_status
        case status
        when 0 then nil
        when 2
          abort <<~EOS
            `terraform plan` for #{env} is not empty.  An upgrade started from a dirty plan
            inherits whatever drift is already there.  Reconcile it first.
          EOS
        else
          abort "`terraform plan` for #{env} failed (exit #{status})."
        end
      end

      # ------------------------------------------------------------- terraform

      def terraform
        @terraform ||= Terraform.new env
      end

      def config
        @config ||= TerraformConfig.new File.join("config/subspace/terraform", env, "main.tf")
      end

      def address(resource)
        "module.#{config.module_name}.#{resource}"
      end

      def instance_ssh_phase?
        State.exist?(env) && INSTANCE_SSH_PHASES.include?(state.phase)
      end

      # The module toggles a self-referencing ingress rule on the server group in place.
      def instance_ssh_change
        { address("aws_security_group.single") => ["update"] }
      end

      # Save main.tf and apply, but only if the plan does exactly what this phase expects.
      # `expected` maps a resource address to the actions permitted for it.  Anything short
      # of an attempted apply puts main.tf back, so the next phase does not start from a
      # dirty plan.  A failed apply does not, since terraform may have applied part of it,
      # and `starting` is recorded as the phase so the step can be re-run to finish it.
      def apply!(expected, starting: nil)
        config.save
        begin
          changes = terraform.plan_changes
          unexpected = changes.reject do |change|
            permitted = expected[change["address"]]
            permitted && (change["change"]["actions"] - permitted).empty?
          end

          if unexpected.any?
            say "Refusing to apply.  This plan does things this step did not ask for:"
            unexpected.each { |change| say "  #{change["change"]["actions"].join(",")} #{change["address"]}" }
            terraform.discard_plan
            abort "Reconcile the drift and try again."
          end

          say "#{template} #{env}: terraform will"
          changes.each { |change| say "  #{change["change"]["actions"].join(",")} #{change["address"]}" }
          unless ask("Apply this plan? [no] ").downcase.start_with? "y"
            terraform.discard_plan
            abort "Aborted."
          end
        rescue StandardError, SystemExit, Interrupt
          config.revert
          raise
        end
        state.advance! starting if starting
        terraform.apply_plan
        config.mark_applied
      end

      # ------------------------------------------------------------- inventory

      def update_inventory!
        inventory.merge terraform.output("inventory")
        inventory.write
        @inventory = nil
      end

      def learn_host_key!(address)
        system "ssh-keygen", "-R", address
        system "ssh-keyscan -H #{address} >> ~/.ssh/known_hosts"
      end

      def add_to_group!(hostname, group)
        host = inventory.hosts.fetch hostname
        host.group_list |= [group]
        inventory.write
        @inventory = nil
      end

      def remove_from_group!(hostname, group)
        host = inventory.hosts.fetch hostname
        host.group_list -= [group]
        inventory.write
        @inventory = nil
      end

      def remove_host!(hostname)
        inventory.hosts.delete hostname
        inventory.write
        @inventory = nil
      end

      # --------------------------------------------------------------- helpers

      def state
        @state ||= begin
          unless State.exist? env
            abort "No upgrade in progress for #{env}.  Start one with `subspace upgrade #{env} --init`."
          end

          State.read env
        end
      end

      def manifest
        @manifest ||= ModuleManifest.read(module_dir) || remote_manifest
      end

      # Older projects reference the module by git URL rather than vendoring it, so the
      # ref is only recorded in the `?ref=` of main.tf's source argument.
      def remote_manifest
        source = File.read(config.path)[/^[ \t]*source[ \t]*=[ \t]*"([^"]+)"/, 1]
        return nil if source.nil? || source.start_with?(".")

        ref = source[/\?ref=(.+)\z/, 1]
        return nil if ref.nil?

        { "template" => template, "repo" => source.split("?").first, "ref" => ref }
      end

      def module_dir
        File.join "config/subspace/terraform", env, "modules", template
      end

      def module_source_dir
        return module_dir if Dir.exist? module_dir

        File.join "config/subspace/terraform", env, ".terraform/modules", config.module_name
      end

      def aws_profile
        "subspace-#{project_name}"
      end

      def update_gitignore!
        path = "config/subspace/terraform/.gitignore"
        existing = File.exist?(path) ? File.readlines(path, chomp: true) : []
        missing = File.readlines(File.join(template_dir, "terraform/.gitignore"), chomp: true) - existing
        return if missing.empty?

        File.write path, (existing + missing).map { |line| "#{line}\n" }.join
        say "Added #{missing.join(", ")} to #{path}"
      end

      def assert_clean_git_tree!
        return if `git status --porcelain -- . ":(exclude)#{State.path_for env}"`.strip.empty?

        abort "The working tree is dirty.  Commit or stash first -- every config change an upgrade makes should be reviewable on its own."
      end

      # Ansible exits 0 on a hosts: pattern that matches nothing, so every gate built on
      # one would pass having asserted nothing.  --limit exits 1 instead.
      def playbook(name, hosts, **extra_vars)
        ansible_playbook File.join(playbook_dir, "#{name}.yml"),
          "--limit", Array(hosts).join(","),
          "-e", extra_vars.to_json
      end

      # A module pinned to a branch rather than a tag has no version to compare, so treat
      # it as too old and send the operator through the migration instructions.
      def gem_version(ref)
        Gem::Version.new ref.to_s.sub(/\Av/, "")
      rescue ArgumentError
        Gem::Version.new "0"
      end

      def locally_modified_module?
        return false if manifest.nil? || !Dir.exist?(module_dir)

        Dir.mktmpdir do |tmp|
          reference = File.join tmp, "reference"
          cloned = system("git", "clone", "--depth", "1", "--branch", manifest["ref"],
            manifest["repo"], reference, out: File::NULL, err: File::NULL)
          abort "Could not clone #{manifest["repo"]} at #{manifest["ref"]} to check #{module_dir} for local changes." unless cloned

          FileUtils.rm_rf File.join(reference, ".git")
          !system("diff", "-r", "-q",
            "--exclude=#{ModuleManifest::FILENAME}",
            "--exclude=.terraform",
            "--exclude=.terraform.lock.hcl",
            reference, module_dir, out: File::NULL, err: File::NULL)
        end
      end
    end
  end
end
