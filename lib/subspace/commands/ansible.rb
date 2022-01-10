module Subspace
  module Commands
    module Ansible
      def ansible_command(command, *args)
        update_ansible_cfg
        Dir.chdir "config/subspace" do
          say ">> Running #{command} #{args.join(' ')}"
          system(command, *args, out: $stdout, err: $stderr)
          say "<< Done"
        end
      end

      private

      def update_ansible_cfg
        template! "ansible.cfg"
      end
    end
  end
end
