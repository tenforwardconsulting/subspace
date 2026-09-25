require 'json'
require 'open3'
module Subspace
  module Upgrade
    # Terraform invocations for an environment, including the saved-plan review that
    # every destructive step in an upgrade goes through.
    class Terraform
      PLAN_FILE = "subspace-upgrade.tfplan"

      def initialize(env)
        @dir = File.join "config/subspace/terraform", env
      end

      def run(*args)
        result = nil
        Dir.chdir @dir do
          puts ">> terraform #{args.join(' ')}"
          result = system("terraform", *args, out: $stdout, err: $stderr)
        end
        result
      end

      def capture(*args)
        stdout, stderr, status = Open3.capture3("terraform", *args, chdir: @dir)
        abort "terraform #{args.join(' ')} failed:\n#{stderr}" unless status.success?
        stdout
      end

      def state_list
        capture("state", "list").split("\n").map(&:strip)
      end

      def output(name)
        JSON.parse capture("output", "-json", name)
      end

      def terraform_cloud?
        File.read(File.join(@dir, "main.tf")) =~ /^\s+cloud \{$/
      end

      # 0 = no changes, 2 = changes pending, anything else = terraform failed
      def plan_exit_status
        Dir.chdir @dir do
          system("terraform", "plan", "-detailed-exitcode", "-input=false", out: $stdout, err: $stderr)
        end
        $?.exitstatus
      end

      # Every change the plan proposes, excluding resources terraform leaves alone
      def plan_changes
        run("plan", "-input=false", "-out=#{PLAN_FILE}") or abort "terraform plan failed"
        JSON.parse(capture("show", "-json", PLAN_FILE))
          .fetch("resource_changes", [])
          .reject { |change| change["change"]["actions"] == ["no-op"] }
      end

      def apply_plan
        run("apply", "-input=false", PLAN_FILE) or abort "terraform apply failed"
        discard_plan
      end

      def discard_plan
        File.delete File.join(@dir, PLAN_FILE) if File.exist? File.join(@dir, PLAN_FILE)
      end
    end
  end
end
