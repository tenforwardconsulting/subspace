require 'subspace/commands/ansible'
module Subspace
  module Commands
    class Base < Commander::Command
      include Subspace::Commands::Ansible
      def template_dir
        File.join(gem_path, 'template', 'provision')
      end

      def gem_path
        File.expand_path '../../../..', __FILE__
      end

      def dest_dir
        "config/provision"
      end

      def template(src, dest = nil)
        dest ||= src
        template = ERB.new File.read(File.join(template_dir, "#{src}.erb")), nil, '-'
        File.write File.join(dest_dir, dest), template.result(binding)
      end
    end
  end
end
