require 'digest'
require 'fileutils'
require 'yaml'
require 'subspace/version'
module Subspace
  module Upgrade
    module ModuleManifest
      FILENAME = "module.yml"

      def self.bundled_dir(template)
        File.expand_path "../../../terraform/modules/#{template}", __dir__
      end

      def self.vendor(template, module_dir)
        FileUtils.cp_r bundled_dir(template), module_dir
        File.write File.join(module_dir, FILENAME),
          YAML.dump("template" => template, "version" => Subspace::VERSION, "checksums" => checksums(module_dir))
      end

      # Modules not bundled with the gem yet are cloned, so they are versioned by git ref
      def self.write(module_dir, template:, repo:, ref:)
        File.write File.join(module_dir, FILENAME),
          YAML.dump("template" => template, "repo" => repo, "ref" => ref)
      end

      def self.read(module_dir)
        path = File.join module_dir, FILENAME
        YAML.load_file(path) if File.exist? path
      end

      def self.modified_files(module_dir)
        recorded = read(module_dir).to_h.fetch("checksums", {})
        current = checksums module_dir
        (recorded.keys | current.keys).reject { |file| recorded[file] == current[file] }.sort
      end

      def self.checksums(module_dir)
        Dir.glob("**/*", base: module_dir)
          .reject { |file| file == FILENAME || File.directory?(File.join(module_dir, file)) }
          .sort
          .to_h { |file| [file, Digest::SHA256.file(File.join(module_dir, file)).hexdigest] }
      end
    end
  end
end
