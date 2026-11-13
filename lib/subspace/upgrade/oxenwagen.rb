module Subspace
  module Upgrade
    # N web servers behind an ALB, with RDS and ElastiCache alongside.  An OS upgrade stands
    # up a full replacement set of web and worker slots outside the load balancer, provisions
    # and verifies them, hands the workers over, attaches the new web servers and waits for
    # AWS to report them healthy, drains and detaches the old ones, then destroys the old slots.
    class Oxenwagen < Base
      TEMPLATE = "oxenwagen"
      KEYED_RESOURCES = ["aws_instance.web", "aws_instance.worker"]
      REQUIRED_MODULE_VARIABLES = %w[web_instances worker_instances lb_instances]
      REQUIRED_ROOT_OUTPUTS = %w[inventory web_instances worker_instances lb_instances lb_target_group_arn]
      STATE_REQUIRES = ["aws_lb.", "aws_db_instance.", "aws_instance.web"]
      STATE_FORBIDS = ["aws_instance.single"]
      SERVER_LINE = /^[ \t]*server[ \t]+.*\n/
      HEALTH_TIMEOUT = 600
      HEALTH_POLL_INTERVAL = 15

      # Every resource keyed by an instance slot, so one apply covers a whole slot.
      RESOURCES_PER_SLOT = {
        "web" => ["aws_instance.web", "aws_eip.web", "aws_eip_association.eip_assoc", "aws_route53_record.web"],
        "worker" => ["aws_instance.worker", "aws_eip.worker", "aws_eip_association.worker_eip_assoc", "aws_route53_record.worker"],
        "lb" => ["aws_lb_target_group_attachment.web"],
      }

      def check
        check_has_workers!
        check_elastic_ip_headroom! unless State.exist? env
        super
      end

      def launch
        state.require_phase! "initialized", "launching"
        if state.phase == "initialized"
          check!
          check_has_workers!
          check_elastic_ip_headroom!
          check_subspace_key!
          check_set_is_finalized!
          assert_clean_git_tree!
          add_next_instances!
        else
          check! clean_plan: false
        end

        apply!(slot_changes("web", to_slots("web"), ["create"])
          .merge(slot_changes("worker", to_slots("worker"), ["create"])),
          starting: "launching")

        update_inventory!
        to_hostnames.each { |hostname| add_to_group! hostname, "upgrade" }

        state.advance! "launched"
        say next_step_for "launched"
      end

      def provision
        state.require_phase! "launched", "prepared"
        check!

        to_hostnames.each { |hostname| Subspace::Commands::Bootstrap.new [hostname], options }
        provision! to_hostnames
        to_hostnames.each { |hostname| join_tailnet! hostname }
        to_hostnames("worker").each { |hostname| mask_cron! hostname }
        write_capistrano_stage!

        state.advance! "prepared"
        say next_step_for "prepared"
      end

      def copy_db
        abort "#{env} keeps its database in RDS, which both the old and new servers share.  There is nothing to copy."
      end

      def close_instance_ssh
        abort "#{env}'s servers reach each other through #{template}'s internal security group, which an upgrade never opens or closes."
      end

      def cutover
        state.require_phase! "prepared", "cutting_over"
        if state.phase == "prepared"
          check!
          to_hostnames("web").each { |hostname| verify_deployed! hostname }
          to_hostnames("worker").each { |hostname| verify_worker! hostname }
          check_same_release!

          say "This puts #{to_hostnames("web").join ", "} into #{env}'s load balancer, waits for AWS"
          say "to report them healthy, then drains and removes #{from_hostnames("web").join ", "}."
          say "Once this finishes there is no --abort.  Nothing is destroyed until --finalize, so the"
          say "old servers stay up, but #{env} is committed to the new set."
          abort "Aborted." unless ask("Continue? [no] ").downcase.start_with? "y"
          state.advance! "cutting_over"
        else
          check! clean_plan: false
        end

        hand_workers_over!
        attach!
        wait_until_healthy! to_instance_ids("web")
        detach!
        wait_until_drained! from_instance_ids("web")
        promote_capistrano_stage!

        state.advance! "cutover"
        say next_step_for "cutover"
      end

      def finalize
        state.require_phase! "cutover", "finalizing"
        if state.phase == "cutover"
          check!

          say "This permanently destroys #{from_hostnames.join ", "}."
          say "#{env} has been running on #{to_hostnames.join ", "} since --cutover.  The database,"
          say "the redis cluster and the S3 bucket are shared and are not touched."
          abort "Aborted." unless ask("Type the environment name to confirm: ").strip == env

          %w[web worker].each do |kind|
            from_slots(kind).each { |slot| config.remove_instance slot, map: "#{kind}_instances" }
          end
        else
          check! clean_plan: false
        end

        apply!(slot_changes("web", from_slots("web"), ["delete"])
          .merge(slot_changes("worker", from_slots("worker"), ["delete"])),
          starting: "finalizing")

        from_hostnames.each { |hostname| remove_host! hostname }
        to_hostnames.each { |hostname| remove_from_group! hostname, "upgrade" }

        state.advance! "finalized"
        say "#{env} is running on #{to_hostnames.join ", "} (#{state["to_ami"]}).  Commit the config diff."
      end

      def abort_upgrade
        state.require_phase! "launching", "launched", "prepared", "cutting_over", "aborting"
        check! clean_plan: false
        check_old_set_attached!
        say "This destroys #{to_hostnames.join ", "} and leaves #{env} on #{from_hostnames.join ", "}."
        abort "Aborted." unless ask("Type the environment name to confirm: ").strip == env

        detach_new!
        if state.phase == "cutting_over"
          to_hostnames("worker").each { |hostname| mask_cron! hostname }
          from_hostnames("worker").each { |hostname| start_application! hostname }
        end

        state.advance! "aborting"
        to_hostnames.each { |hostname| remove_host! hostname }
        FileUtils.rm_f capistrano_stage_path

        %w[web worker].each do |kind|
          map = "#{kind}_instances"
          (to_slots(kind) & config.instances(map).keys).each { |slot| config.remove_instance slot, map: map }
        end
        apply!(slot_changes("web", to_slots("web"), ["delete"])
          .merge(slot_changes("worker", to_slots("worker"), ["delete"])),
          starting: "aborting")

        state.destroy
        say "Aborted the upgrade.  Commit the config diff."
      end

      private

      # --------------------------------------------------------- data

      # The db role, and so migrations, lives on a worker, and web servers must not run
      # background work or cron.
      def check_has_workers!
        return if config.instances("worker_instances").any?

        abort "#{config.path} has no worker_instances.  `subspace upgrade` needs at least one worker to hold the db role."
      end

      # A web slot that is not attached to the load balancer is left over from an upgrade that
      # never finalized.  Starting another would stack a third set on top of it.
      def check_set_is_finalized!
        detached = config.instances("web_instances").keys - config.list_argument("lb_instances")
        return if detached.empty?

        abort <<~EOS
          #{config.path} has web slots that are not in lb_instances: #{detached.join ", "}.
          A previous upgrade did not finish.  Finalize or abort it before starting another.
        EOS
      end

      # Once the detach has landed the old servers are drained and out of the load balancer, so
      # backing out would empty it.  That is past the commitment; only --cutover goes on from here.
      def check_old_set_attached!
        return if (from_slots("web") - config.list_argument("lb_instances")).empty?

        abort <<~EOS
          #{from_hostnames("web").join ", "} #{from_hostnames("web").one? ? "is" : "are"} already out of #{env}'s load balancer and
          #{to_hostnames("web").join ", "} #{to_hostnames("web").one? ? "is" : "are"} serving.  There is no --abort from here.
          Finish with `subspace upgrade #{env} --cutover`.
        EOS
      end

      # Every instance needs an elastic IP to reach the internet at all, and an upgrade holds
      # two sets at once, so a default quota of 5 stops a 3-server environment half-applied.
      def check_elastic_ip_headroom!
        needed = new_elastic_ips
        headroom = Ec2.elastic_ip_headroom profile: aws_profile
        return if headroom >= needed

        abort <<~EOS
          Upgrading #{env} needs #{needed} more elastic IPs and this region has room for #{headroom}.
          Raise the EC2-VPC Elastic IP quota before starting, or the launch stops half-applied.
        EOS
      end

      def add_next_instances!
        state["to_ami"] = target_ami
        state["ubuntu_release"] = options.ami ? options.ubuntu_release : ubuntu_release
        %w[web worker].each { |kind| plan_slots! kind }
        state.save

        %w[web worker].each do |kind|
          slots_for(kind).each do |from_slot, slot|
            say "Upgrading #{template} #{env}: #{kind} slot #{from_slot} (#{slot["from_hostname"]}) => slot #{slot["to_slot"]} (#{slot["to_hostname"]})"
          end
        end
      end

      def plan_slots!(kind)
        map = "#{kind}_instances"
        existing = config.instances map
        taken = existing.values.map { |attributes| TerraformConfig.unquote attributes["hostname"] }
        next_key = existing.keys.map(&:to_i).max.to_i
        slots = {}

        existing.each do |from_slot, attributes|
          next_key += 1
          from_hostname = TerraformConfig.unquote attributes["hostname"]
          to_hostname = next_hostname from_hostname, taken
          taken << to_hostname
          slots[from_slot] = {
            "to_slot" => next_key.to_s,
            "from_hostname" => from_hostname,
            "to_hostname" => to_hostname,
          }
          config.add_instance next_key.to_s,
            attributes.merge("hostname" => %("#{to_hostname}"), "ami" => %("#{state["to_ami"]}")),
            map
        end

        state["#{kind}_slots"] = slots
      end

      # dev-web1 => dev-web3 when dev-web2 is taken.  The slot key and the hostname number are
      # independent, so derive the name from the host being replaced rather than from the key.
      def next_hostname(from_hostname, taken)
        abort "Could not derive a hostname from '#{from_hostname}'.  Rename it to end in a number." unless from_hostname.match?(/\d\z/)

        hostname = from_hostname
        hostname = hostname.sub(/(\d+)\z/) { $1.to_i + 1 } while taken.include? hostname
        hostname
      end

      def new_elastic_ips
        config.instances("web_instances").size + config.instances("worker_instances").size
      end

      def slots_for(kind)
        state["#{kind}_slots"].to_h
      end

      def from_slots(kind)
        slots_for(kind).keys
      end

      def to_slots(kind)
        slots_for(kind).values.map { |slot| slot["to_slot"] }
      end

      def from_hostnames(*kinds)
        hostnames kinds, "from_hostname"
      end

      def to_hostnames(*kinds)
        hostnames kinds, "to_hostname"
      end

      def hostnames(kinds, key)
        kinds = %w[web worker] if kinds.empty?
        kinds.flat_map { |kind| slots_for(kind).values.map { |slot| slot[key] } }
      end

      def from_instance_ids(kind)
        instance_ids kind, from_slots(kind)
      end

      def to_instance_ids(kind)
        instance_ids kind, to_slots(kind)
      end

      def instance_ids(kind, slots)
        output = terraform.output "#{kind}_instances"
        slots.map { |slot| output.fetch(slot).fetch("id") }
      end

      # --------------------------------------------------------- terraform

      def slot_changes(kind, slots, actions)
        RESOURCES_PER_SLOT.fetch(kind).product(slots).to_h do |resource, slot|
          [address(%(#{resource}["#{slot}"])), actions]
        end
      end

      # Old first: a few seconds with no cron is safe, a few seconds with two is not.
      def hand_workers_over!
        from_hostnames("worker").each { |hostname| stop_application! hostname }
        to_hostnames("worker").each { |hostname| unmask_cron! hostname }
      end

      def attach!
        attached = config.list_argument "lb_instances"
        done = (to_slots("web") - attached).empty?
        check_lb_record! "lb_attached", done, to_slots("web")
        return if state["lb_attached"]

        config.set_list_argument "lb_instances", attached | to_slots("web")
        apply! slot_changes("lb", to_slots("web"), ["create"])
        record_lb! "lb_attached", true
      end

      def detach!
        attached = config.list_argument "lb_instances"
        done = (from_slots("web") & attached).empty?
        check_lb_record! "lb_detached", done, from_slots("web")
        return if state["lb_detached"]

        config.set_list_argument "lb_instances", attached - from_slots("web")
        apply! slot_changes("lb", from_slots("web"), ["delete"])
        record_lb! "lb_detached", true
      end

      def record_lb!(key, value)
        state[key] = value
        state.save
      end

      # upgrade.yml is written only after an apply lands, so it can only claim a step main.tf
      # does not show if main.tf was edited by hand.  The reverse is a failed or partial apply,
      # which re-applying finishes.
      def check_lb_record!(key, done, slots)
        return unless state[key] && !done

        abort <<~EOS
          #{State.path_for env} says #{key} is true, but lb_instances in #{config.path}
          says it has not happened for slot#{"s" unless slots.one?} #{slots.join ", "}.
          One of the two has been edited by hand.  Reconcile them before continuing.
        EOS
      end

      def detach_new!
        attached = config.list_argument "lb_instances"
        return if (to_slots("web") & attached).empty?

        config.set_list_argument "lb_instances", attached - to_slots("web")
        apply! slot_changes("lb", to_slots("web"), ["delete"])
        record_lb! "lb_attached", false
        wait_until_drained! to_instance_ids("web")
      end

      def wait_until_healthy!(instance_ids)
        say "Waiting for AWS to report #{instance_ids.join ", "} healthy in the target group"
        attempts = HEALTH_TIMEOUT / HEALTH_POLL_INTERVAL
        loop do
          states = target_states instance_ids
          return if states.values.all? { |state| state == "healthy" }

          attempts -= 1
          if attempts.zero?
            abort <<~EOS
              AWS has not reported the new web servers healthy within #{HEALTH_TIMEOUT / 60} minutes:
                #{states.map { |id, state| "#{id} #{state || "not registered"}" }.join "\n  "}
              They are attached but taking no traffic, and #{from_hostnames("web").join ", "}
              #{from_hostnames("web").one? ? "is" : "are"} still serving every request.  Fix them, then re-run
              `subspace upgrade #{env} --cutover` -- or `subspace upgrade #{env} --abort`.
            EOS
          end

          say "  #{states.reject { |_, state| state == "healthy" }.map { |id, state| "#{id} #{state || "not registered"}" }.join ", "}"
          sleep HEALTH_POLL_INTERVAL
        end
      end

      def wait_until_drained!(instance_ids)
        say "Waiting for #{instance_ids.join ", "} to finish draining"
        attempts = HEALTH_TIMEOUT / HEALTH_POLL_INTERVAL
        loop do
          states = target_states(instance_ids).compact
          return if states.empty?

          attempts -= 1
          if attempts.zero?
            abort <<~EOS
              #{states.keys.join ", "} #{states.one? ? "is" : "are"} still registered with the target group after
              #{HEALTH_TIMEOUT / 60} minutes.  The new servers are live and serving.  Leave the old
              ones alone and re-run `subspace upgrade #{env} --cutover` to finish.
            EOS
          end

          say "  #{states.map { |id, state| "#{id} #{state}" }.join ", "}"
          sleep HEALTH_POLL_INTERVAL
        end
      end

      def target_states(instance_ids)
        health = Elb.target_health terraform.output("lb_target_group_arn"), profile: aws_profile
        instance_ids.to_h { |id| [id, health[id]] }
      end

      # --------------------------------------------------------- application

      def verify_worker!(hostname)
        playbook_or_abort "upgrade_verify_worker", hostname
      end

      def mask_cron!(hostname)
        say "Masking cron on #{hostname} until --cutover, so it does not run beside #{from_hostnames("worker").join ", "}"
        playbook_or_abort "upgrade_mask_cron", hostname
      end

      def unmask_cron!(hostname)
        say "Unmasking cron on #{hostname}"
        playbook_or_abort "upgrade_unmask_cron", hostname
      end

      def check_same_release!
        hosts = from_hostnames("web") + to_hostnames("web")
        return if playbook "upgrade_release", hosts, upgrade_hosts: hosts.join(",")

        abort "The web servers are not all on the same release, so assets would 404 during the overlap."
      end

      # ---------------------------------------------------------- capistrano

      def write_capistrano_stage!
        base_stage = File.read base_stage_path
        abort "No server line in #{base_stage_path} to replace with #{to_hostnames.join ", "}." unless base_stage.match? SERVER_LINE

        extras = server_options base_stage[SERVER_LINE]
        hosts = to_hostnames.map { |name| inventory.hosts.fetch name }
        block = Subspace::Commands::Inventory.server_lines(hosts).map { |line| "#{line.sub(" # ", "#{extras} # ")}\n" }.join
        written = false
        stage = base_stage.gsub(SERVER_LINE) do
          next "" if written

          written = true
          block
        end

        File.write capistrano_stage_path, stage_header + stage
        say <<~EOS
          Wrote #{capistrano_stage_path}.  Compare it with #{base_stage_path} line by line before deploying.
          It has one server line per new host, carrying over #{extras.empty? ? "nothing" : "`#{extras.sub(/\A,\s*/, "")}`"} from the first old
          server line, but every other old server line is gone along with its comments and options.
          Move anything missing across by hand -- --cutover copies this file over #{base_stage_path} as it stands.
        EOS
      end

      # Copied rather than regenerated, so whatever was moved across by hand after --provision survives.
      def promote_capistrano_stage!
        File.write base_stage_path, File.read(capistrano_stage_path).delete_prefix(stage_header)
        FileUtils.rm_f capistrano_stage_path
        say "Pointed #{base_stage_path} at #{to_hostnames.join ", "}"
      end

      def stage_header
        "# Generated by Subspace from #{base_stage_path}\nset :stage, :#{env}\n"
      end

      # Whatever the first server line sets beyond its address, user and roles, e.g. ssh_options.
      def server_options(line)
        line.chomp
          .sub(/\A[ \t]*server[ \t]+(["'])[^"']*\1/, "")
          .sub(/,[ \t]*user:[ \t]*(["'])[^"']*\1/, "")
          .sub(/,[ \t]*roles:[ \t]*(%w\{[^}]*\}|\[[^\]]*\])/, "")
          .sub(/[ \t]*#.*\z/, "")
      end

      # --------------------------------------------------------- output

      def slot_summary
        %w[web worker].flat_map do |kind|
          slots_for(kind).map do |from_slot, slot|
            "#{kind.capitalize.ljust 7} #{from_slot} (#{slot["from_hostname"]}) => #{slot["to_slot"]} (#{slot["to_hostname"]})"
          end
        end
      end

      def next_step_for(phase)
        case phase
        when "initialized" then "subspace upgrade #{env} --launch"
        when "launching"
          <<~EOS
            A previous --launch did not finish.  The new servers may or may not exist yet.

              subspace upgrade #{env} --launch   # finish creating them
              subspace upgrade #{env} --abort    # or back out: destroy them

            The old set is still serving all traffic.  Nothing is at risk yet.
          EOS
        when "launched"
          <<~EOS
            The new servers are running but not provisioned yet and are out of the load balancer.

              1. Commit the config diff
              2. subspace upgrade #{env} --provision   # safe to re-run until it succeeds

            The old set is still serving all traffic.  Nothing is at risk yet.
          EOS
        when "prepared"
          <<~EOS
            The new servers are provisioned at their tailscale addresses:
              #{to_hostnames.map { |name| "#{name} #{inventory.hosts[name]&.vars&.dig("ansible_host")}" }.join("\n  ")}

              1. Join them to the tailnet if --provision could not: create a reusable, tagged tailscale auth key
                 (1-day expiry), set tailscale_auth_key in the #{env} vault, then for each host:
                 subspace provision #{env} --tags=tailscale_reauth --limit <hostname>
              2. Compare #{capistrano_stage_path} with #{base_stage_path} line by line and move any
                 dropped comments or options across by hand (--cutover copies it over #{base_stage_path})
              3. bundle exec cap #{env}_upgrade deploy
              4. Deploy the same commit to the base stage so every web server matches:
                 bundle exec cap #{env} deploy
              5. Verify each new web server over the tailnet: http://<tailscale ip>/ (or map the domain
                 to it in /etc/hosts for a faithful test -- there is no https on the instance)
              6. subspace upgrade #{env} --cutover

            The old set is still serving all traffic.  Nothing is at risk yet.
          EOS
        when "cutting_over"
          <<~EOS
            A previous --cutover did not finish.  #{State.path_for env} records the attach of
            #{to_hostnames("web").join ", "} as #{state["lb_attached"] ? "applied" : "not applied"} and the detach of #{from_hostnames("web").join ", "}
            as #{state["lb_detached"] ? "applied" : "not applied"}.  lb_instances in #{config.path} is what is really in the load balancer.

              subspace upgrade #{env} --cutover   # finish moving traffic to the new set
              subspace upgrade #{env} --abort     # or back out, until the old servers have been detached
          EOS
        when "cutover"
          <<~EOS
            The new set is serving through the load balancer and #{base_stage_path} now deploys to it.
            The old servers are still running but out of the load balancer and their background work
            is stopped.

              subspace upgrade #{env} --finalize    # destroy the old servers for good
          EOS
        when "finalizing"
          <<~EOS
            A previous --finalize did not finish.  Some old servers may already be destroyed.

              subspace upgrade #{env} --finalize   # finish destroying the old set
          EOS
        when "aborting"
          <<~EOS
            The old set is back in service.  The new servers have not been destroyed yet.

              subspace upgrade #{env} --abort   # destroy the new servers
          EOS
        when "finalized" then "Nothing.  This upgrade is done -- commit the config diff and delete #{State.path_for env}."
        end
      end

      def migration_instructions
        <<~EOS
          To migrate #{env} (one time, no downtime):

            1. Re-vendor the module:
                 subspace upgrade #{env} --revendor   # copies the module from subspace #{Subspace::VERSION}, keeps a .bak
            2. Install the vendored module:
                 terraform init
            3. Convert this environment to instance slots:
                 subspace upgrade #{env} --migrate    # prints the exact config and state moves,
                                                      # then makes them and proves the plan is empty
        EOS
      end
    end
  end
end
