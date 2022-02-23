require 'json'
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
        check_aws_credentials or exit
        ensure_terraform or exit
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

      def check_aws_credentials
        ENV["AWS_ACCESS_KEY_ID"] = nil
        ENV["AWS_SECRET_ACCESS_KEY"] = nil

        profile = "subspace-#{project_name}"

        system("aws --profile #{profile} configure list &> /dev/null ")
        if $? != 0
          puts "No AWS Profile '#{profile}' configured.  Please enter your credentials."
          system("aws --profile #{profile} configure")
          system("aws --profile #{profile} configure list &> /dev/null ")
          if $? != 0
            puts "FATAL: could not configure aws.  Please try again"
            exit
          end
        else
          puts "Using AWS Profile #{profile}"
        end
        true
      end

      def ensure_terraform
         if `terraform -v --json | jq -r .terraform_version` =~ /1\.\d+/
            puts "Terraform found."
            return true
         else
            puts "Please install terraform at least 1.1 locally"
            return false
         end
      end
    end
  end
end
