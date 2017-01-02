require 'subspace/commands/ansible'
module Subspace
  module Commands
    class Base < Commander::Command
      include Subspace::Commands::Ansible

      def require_configuration
        load "config/provision.rb"
      end

      def template_dir
        File.join(gem_path, 'template', 'provision')
      end

      def gem_path
        File.expand_path '../../../..', __FILE__
      end

      def dest_dir
        "config/provision"
      end

      def template(src, dest = nil, render_binding = nil)
        dest ||= src
        template = ERB.new File.read(File.join(template_dir, "#{src}.erb")), nil, '-'
        File.write File.join(dest_dir, dest), template.result(render_binding || binding)
      end

      def copy(src, dest = nil)
        dest ||= src
        FileUtils.cp File.join(template_dir, src), File.join(dest_dir, dest)
      end

    end
  end
end
