module Subspace
  module Commands
    module Ansible
      def ansible_command(command, *args)
        Dir.chdir "config/provision" do
          say ">> Running #{command} #{args.join(' ')}"
          system(command, *args, out: $stdout, err: $stderr)
          say "<< Done"
        end
      end


    end
  end
end
