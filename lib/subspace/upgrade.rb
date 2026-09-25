require 'fileutils'
require 'tmpdir'
require 'commander'
require 'subspace/ami'
require 'subspace/inventory'
require 'subspace/commands/base'
require 'subspace/commands/bootstrap'
require 'subspace/commands/db_copy'
require 'subspace/commands/init'
require 'subspace/commands/inventory'
require 'subspace/upgrade/module_manifest'
require 'subspace/upgrade/state'
require 'subspace/upgrade/terraform_config'
require 'subspace/upgrade/terraform'
require 'subspace/upgrade/base'
require 'subspace/upgrade/workhorse'
require 'subspace/upgrade/oxenwagen'

module Subspace
  module Upgrade
    STRATEGIES = {
      "workhorse" => Subspace::Upgrade::Workhorse,
      "oxenwagen" => Subspace::Upgrade::Oxenwagen,
    }

    # Determine workhorse vs oxenwagen - fails hard if not 100% sure
    def self.strategy_for(env, options)
      env_dir = File.join "config/subspace/terraform", env
      recorded = State.exist?(env) ? State.read(env)["template"] : nil
      vendored = Dir[File.join(env_dir, "modules", "*")]
        .select { |dir| File.directory? dir }
        .map { |dir| ModuleManifest.read(dir)&.fetch("template", nil) }
        .compact
      main_tf = File.read File.join(env_dir, "main.tf")
      sourced = main_tf[%r{terraform-subspace-(\w+)}, 1] || main_tf[%r{source\s*=\s*"\./modules/(\w+)"}, 1]

      templates = ([recorded, sourced] + vendored).compact.uniq
      if templates.size > 1
        abort <<~EOS
          #{env} does not agree with itself about which template it uses:
            #{State.path_for env} says #{recorded || "(nothing)"}
            #{File.join env_dir, "main.tf"} says #{sourced || "(nothing)"}
            #{File.join env_dir, "modules"} contains #{vendored.empty? ? "(nothing)" : vendored.join(", ")}
          Refusing to run any upgrade step until that is resolved.
        EOS
      end

      template = templates.first
      if template.nil?
        abort <<~EOS
          Could not determine which terraform template #{env} uses.  `subspace upgrade` reads it
          from the module source in #{File.join env_dir, "main.tf"} and from the
          #{ModuleManifest::FILENAME} manifest in #{File.join env_dir, "modules"}.
        EOS
      end

      strategy = STRATEGIES[template]
      abort "Unknown terraform template '#{template}'." if strategy.nil?

      strategy.new env, options
    end
  end
end
