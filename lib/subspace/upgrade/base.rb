module Subspace
  module Upgrade
    # Shared machinery for every topology's upgrade.  Subclasses own the actual
    # sequence; nothing in here branches on the template.
    class Base < Subspace::Commands::Base
      MINIMUM_MODULE_REF = "v2.0.0"

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
        say "#{env} is on #{template} #{manifest["ref"]} and ready for `subspace upgrade`."
      end

      def status
        unless State.exist? env
          say "No upgrade in progress for #{env}.  Start one with `subspace upgrade #{env} --init`."
          return
        end

        say "Template:  #{state["template"]}"
        say "Phase:     #{state["phase"]}"
        say "Slots:     #{state["from_slot"]} (#{state["from_ami"]}) => #{state["to_slot"]} (#{state["to_ami"]})"
        say "Backup:    #{state["backup_path"]} (#{state["backup_bytes"]} bytes)" if state["backup_path"]
        state["log"].to_a.each { |entry| say "  #{entry["at"]}  #{entry["phase"]}" }

        if state["window_open"]
          say ""
          say "The maintenance window is OPEN: #{state["from_hostname"]} has puma, the workers and cron"
          say "stopped and is showing the maintenance page.  `--cutover` or `--abort` closes it."
        end

        if config.allow_instance_ssh
          say ""
          say "WARNING: allow_instance_ssh is still true.  Instances can ssh to each other."
          say "Close it with `subspace upgrade #{env} --close-instance-ssh`."
        end

        say ""
        say "Next:      #{next_step_for state.phase}"
      end

      def init
        check!
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
        apply!({ address("aws_security_group.instance_ssh[0]") => ["delete"] }
                 .merge(slot_addresses("update")))
      end

      # Copy the upstream module in again, keeping the old copy as a .bak
      def revendor
        mod = Subspace::Commands::Init::TERRAFORM_MODULES.fetch template
        if locally_modified_module?
          abort <<~EOS
            #{module_dir} has been modified locally (its manifest says #{manifest["ref"]}
            but the files do not match that ref).  Re-vendoring would throw those changes away.
            Reconcile them by hand, then re-run with a matching manifest.
          EOS
        end

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
          FileUtils.mv backup, module_dir if backup
          abort "Failed to clone #{mod[:repo]}.#{" Restored the previous module." if backup}"
        end
        FileUtils.rm_rf File.join(module_dir, ".git")
        FileUtils.rm_f File.join(module_dir, ".gitmodules")
        ModuleManifest.write module_dir, template: template, repo: mod[:repo], ref: mod[:ref]

        say ""
        say migration_instructions
      end

      # --------------------------------------------------------- compatibility

      def check!
        check_module_version!
        check_module_variables!
        check_root_outputs!
        check_state_fingerprint!
        check_instance_ssh_closed!
        check_clean_plan!
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

      def check_instance_ssh_closed!
        return unless config.allow_instance_ssh

        abort <<~EOS
          allow_instance_ssh is true in #{config.path}, which means the instances in #{env}
          can still ssh to each other.  It should only be open during a db copy.

          Close it:  subspace upgrade #{env} --close-instance-ssh
        EOS
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

      # Toggling allow_instance_ssh rebuilds the same security-group list on every slot,
      # so the plan holds one in-place update per slot, not just the one being added.
      def slot_addresses(*actions)
        config.instances.keys.to_h do |key|
          [address(%(#{self.class::KEYED_RESOURCE}["#{key}"])), actions]
        end
      end

      # Save main.tf and apply, but only if the plan does exactly what this phase expects.
      # `expected` maps a resource address to the actions permitted for it.  Anything short
      # of an attempted apply puts main.tf back, so the next phase does not start from a
      # dirty plan.  A failed apply does not, since terraform may have applied part of it.
      def apply!(expected)
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
        rescue SystemExit, Interrupt
          config.revert
          raise
        end
        terraform.apply_plan
        config.mark_applied
      end

      # ------------------------------------------------------------- inventory

      def update_inventory!
        inventory.merge terraform.output("inventory")
        inventory.write
        @inventory = nil
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
        @state ||= State.read env
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

      # Where the module's .tf files actually are: vendored, or downloaded by terraform init
      def module_source_dir
        return module_dir if Dir.exist? module_dir

        File.join "config/subspace/terraform", env, ".terraform/modules", config.module_name
      end

      def aws_profile
        "subspace-#{project_name}"
      end

      def assert_clean_git_tree!
        return if `git status --porcelain`.strip.empty?

        abort "The working tree is dirty.  Commit or stash first -- every config change an upgrade makes should be reviewable on its own."
      end

      # Ansible exits 0 on a hosts: pattern that matches nothing, so every gate built on
      # one would pass having asserted nothing.  --limit exits 1 instead.
      def playbook(name, hosts, *extra_vars)
        ansible_playbook File.join(playbook_dir, "#{name}.yml"),
          "--limit", Array(hosts).join(","),
          *extra_vars.flat_map { |var| ["-e", var] }
      end

      # A module pinned to a branch rather than a tag has no version to compare, so treat
      # it as too old and send the operator through the migration instructions.
      def gem_version(ref)
        Gem::Version.new ref.to_s.sub(/\Av/, "")
      rescue ArgumentError
        Gem::Version.new "0"
      end

      # True if the vendored module's files differ from the upstream ref its manifest names
      def locally_modified_module?
        return false if manifest.nil? || !Dir.exist?(module_dir)

        Dir.mktmpdir do |tmp|
          reference = File.join tmp, "reference"
          cloned = system("git", "clone", "--depth", "1", "--branch", manifest["ref"],
            manifest["repo"], reference, out: File::NULL, err: File::NULL)
          return false unless cloned

          FileUtils.rm_rf File.join(reference, ".git")
          !system("diff", "-r", "-q",
            "--exclude=#{ModuleManifest::FILENAME}",
            "--exclude=#{ModuleManifest::LEGACY_FILENAME}",
            "--exclude=.terraform",
            "--exclude=.terraform.lock.hcl",
            reference, module_dir, out: File::NULL, err: File::NULL)
        end
      end
    end
  end
end
