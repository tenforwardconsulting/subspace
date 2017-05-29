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
        File.join(gem_path, 'template', 'provision')
      end

      def gem_path
        File.expand_path '../../../..', __FILE__
      end

      def project_path
        Dir.pwd # TODO make sure this is correct if they for whatever reason aren't running subspace from the project root??
      end

      def dest_dir
        "config/provision"
      end

      def template(src, dest = nil, render_binding = nil)
        return unless confirm_overwrite File.join(dest_dir, dest || src)
        template! src, dest, render_binding
        say "Wrote #{dest}"
      end

      def template!(src, dest = nil, render_binding = nil)
        dest ||= src
        template = ERB.new File.read(File.join(template_dir, "#{src}.erb")), nil, '-'
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

    end
  end
end
