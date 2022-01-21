require 'json'
require 'debug'
module Subspace
  module Commands
    class Terraform < Subspace::Commands::Base
      def initialize(args, options)
        @env = args.shift
        @args = args
        @options = options
        run
      end

      def run
        if @args.any?
          terraform_command(@args.shift, *@args)
        else
          puts "No command specified, running plan/apply"
          terraform_command("init") or return
          terraform_command("apply") or return
          update_inventory
        end
      end

      private
      def terraform_command(command, *args)
        result = nil
        # update_terraformrc
        Dir.chdir "config/subspace/terraform/#{@env}" do
          say ">> Running terraform #{command} #{args.join(' ')}"
          result = system("terraform", command, *args, out: $stdout, err: $stderr)
          say "<< Done"
        end
        result
      end

      def update_terraformrc
        template! "terraformrc", ".terraformrc"
      end

      def update_inventory
        puts "Apply succeeded, updating inventory."
        Dir.chdir "config/subspace/terraform/#{@env}" do
          @output = JSON.parse `terraform output -json`
        end
        inventory.merge(@output)
        inventory.write
      end
    end
  end
end
