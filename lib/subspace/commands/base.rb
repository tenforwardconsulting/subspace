require 'subspace/commands/ansible'
module Subspace
  module Commands
    class Base < Commander::Command
      include Subspace::Commands::Ansible

      def require_configuration
        load "config/provision.rb"
      end

      def playbook_dir
        File.join(gem_path, 'ansible', 'playbooks')
      end

      def template_dir
        File.join(gem_path, 'template', 'subspace')
      end

      def gem_path
        File.expand_path '../../../..', __FILE__
      end

      def project_path
        unless File.exist?(File.join(Dir.pwd, "config", "subspace"))
          say "Subspace must be run from the project root"
          exit
        end
        Dir.pwd # TODO make sure this is correct if they for whatever reason aren't running subspace from the project root??
      end

      def project_name
        File.basename(project_path) # TODO see above, this should probably be in a configuration somewhere
      end

      def dest_dir
        "config/subspace"
      end

      def template(src, dest = nil, render_binding = nil)
        return unless confirm_overwrite File.join(dest_dir, dest || src)
        template! src, dest, render_binding
        say "Wrote #{dest || src}"
      end

      def template!(src, dest = nil, render_binding = nil)
        dest ||= src
        template = ERB.new File.read(File.join(template_dir, "#{src}.erb")), trim_mode: '-'
        File.write File.join(dest_dir, dest), template.result(render_binding || binding)
      end

      def copy(src, dest = nil)
        dest ||= src
        return unless confirm_overwrite File.join(dest_dir, dest)
        FileUtils.cp File.join(template_dir, src), File.join(dest_dir, dest)
        say "Wrote #{dest}"
      end

      def confirm_overwrite(file_path)
        return true unless File.exists? file_path
        answer = ask "#{file_path} already exists. Reply 'y' to overwrite: [no] "
        return answer.downcase.start_with? "y"
      end

      def pass_through_params
        ansible_options = []
        self.class::PASS_THROUGH_PARAMS.each do |param_name|
          x = param_name.split('-')[1..-1].map(&:upcase).join('_')
          hash_key = (param_name.gsub('-', '_') + (x == '' ? '' : "_#{x}")).to_sym
          value = @options.__hash__[hash_key]
          if value
            if param_name.length > 1
              ansible_options += ["--#{param_name}", value]
            else
              ansible_options += ["-#{param_name}", value]
            end
          end
        end

        ansible_options
      end

      def set_subspace_version
        ENV['SUBSPACE_VERSION'] = Subspace::VERSION
      end

      def inventory
        @inventory ||= Subspace::Inventory.read("config/subspace/inventory.yml")
      end
    end
  end
end
