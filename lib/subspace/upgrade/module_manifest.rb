require 'yaml'
module Subspace
  module Upgrade
    # Records which terraform module a vendored copy came from, so `subspace upgrade`
    # never has to guess the topology it is operating on.
    module ModuleManifest
      FILENAME = "module.yml"

      def self.write(module_dir, template:, repo:, ref:)
        File.write File.join(module_dir, FILENAME),
          YAML.dump("template" => template, "repo" => repo, "ref" => ref)
      end

      def self.read(module_dir)
        path = File.join module_dir, FILENAME
        YAML.load_file(path) if File.exist? path
      end
    end
  end
end
