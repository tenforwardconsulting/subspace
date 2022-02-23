module Subspace
  module Commands
    module Ansible
      def ansible_playbook(*args)
        args.push "--diff"
        args.push "--private-key"
        args.push "subspace.pem"
        ansible_command("ansible-playbook", *args)
      end

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
        if `pip show mitogen` =~ /^Location: (.*?)$/m
          @mitogen_path = $1
          puts "🏎🚀🚅Mitogen found at #{@mitogen_path}.  WARP 9!....ENGAGE!🚀"
        else
          puts "Mitogen not detected.  Ansible will be slow.  Run `pip install mitogen` to fix."
        end
        template! "ansible.cfg"
      end
    end
  end
end
