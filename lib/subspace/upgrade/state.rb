require 'yaml'
require 'time'
module Subspace
  module Upgrade
    # The phase of an in-progress upgrade, committed alongside the terraform config so
    # any operator's working copy agrees on what has already happened.
    class State
      FILENAME = "upgrade.yml"

      attr_reader :data

      def self.path_for(env)
        File.join "config/subspace/terraform", env, FILENAME
      end

      def self.exist?(env)
        File.exist? path_for(env)
      end

      def self.read(env)
        new env, YAML.load_file(path_for(env))
      end

      def self.create(env, attributes)
        new env, attributes
      end

      def initialize(env, data)
        @env = env
        @data = data
      end

      def path
        self.class.path_for @env
      end

      def [](key)
        @data[key.to_s]
      end

      def []=(key, value)
        @data[key.to_s] = value
      end

      def phase
        @data["phase"]
      end

      def require_phase!(*expected)
        return if expected.include? phase

        abort <<~EOS
          This upgrade is at phase '#{phase}', and this step requires #{expected.join(" or ")}.
          Run `subspace upgrade #{@env} --status` to see where things stand.
        EOS
      end

      def advance!(phase)
        @data["phase"] = phase
        @data["log"] ||= []
        @data["log"] << { "phase" => phase, "at" => Time.now.utc.iso8601 }
        save
      end

      def save
        File.write "#{path}.tmp", YAML.dump(@data)
        File.rename "#{path}.tmp", path
      end

      def destroy
        File.delete path if File.exist? path
      end
    end
  end
end
