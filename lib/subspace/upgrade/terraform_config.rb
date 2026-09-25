module Subspace
  module Upgrade
    # Reads and rewrites the `instances` map and the cutover switches in a project's
    # main.tf.  Values are kept as raw HCL literals so a quoted string stays quoted and
    # a number stays a number.
    class TerraformConfig
      attr_reader :path

      def self.unquote(literal)
        literal.to_s.sub(/\A"/, "").sub(/"\z/, "")
      end

      def initialize(path)
        @path = path
        @source = File.read path
        @applied_source = @source.dup
      end

      def module_name
        @source[/^module\s+"?([\w-]+)"?\s*\{/, 1] or raise "No module block found in #{path}"
      end

      def instances
        entry_ranges.transform_values { |range| attributes_in @source[range] }
      end

      def hostname_for(key)
        self.class.unquote instances.fetch(key)["hostname"]
      end

      # Edits splice a single slot's text so comments and anything else in the map survive.
      def add_instance(key, attributes)
        raise "Slot #{key} is already defined in #{path}" if instances.key? key

        indent = @source[/^([ \t]*)instances[ \t]*=/, 1]
        width = attributes.keys.map(&:length).max
        lines = [%(#{indent}  "#{key}" = {)]
        attributes.each { |name, literal| lines << "#{indent}    #{name.ljust(width)} = #{literal}" }
        lines << "#{indent}  }"
        @source.insert @source.rindex("\n", map_range.end) + 1, "#{lines.join("\n")}\n"
      end

      def remove_instance(key)
        range = entry_ranges[key] or raise "There is no slot #{key} in #{path}"

        @source[(@source.rindex("\n", range.begin) + 1)..@source.index("\n", range.end)] = ""
      end

      def active_instance
        @source[/^[ \t]*active_instance[ \t]*=[ \t]*"([^"]*)"/, 1]
      end

      def active_instance=(key)
        set_argument "active_instance", %("#{key}")
      end

      def allow_instance_ssh
        @source[/^[ \t]*allow_instance_ssh[ \t]*=[ \t]*(\S+)/, 1] == "true"
      end

      def allow_instance_ssh=(value)
        set_argument "allow_instance_ssh", value.to_s
      end

      def save
        File.write path, @source
      end

      def mark_applied
        @applied_source = @source.dup
      end

      def revert
        @source = @applied_source.dup
        save
      end

      private

      def set_argument(name, literal)
        pattern = /^([ \t]*)#{name}([ \t]*)=[ \t]*.*$/
        if @source.match? pattern
          @source.sub! pattern, "\\1#{name}\\2= #{literal}"
        else
          anchor = /^([ \t]*)active_instance([ \t]*=.*)$/
          raise "Could not find active_instance in #{path} to anchor #{name}" unless @source.match? anchor

          @source.sub!(anchor) { "#{$1}active_instance#{$2}\n#{$1}#{name} = #{literal}" }
        end
      end

      def map_range
        match = @source.match(/^[ \t]*instances[ \t]*=[ \t]*\{/)
        raise "#{path} has no `instances` map.  Is its terraform module at least v2.0.0?" if match.nil?

        (match.begin(0)..matching_brace(@source, match.end(0) - 1))
      end

      def entry_ranges
        map = map_range
        entries = {}
        cursor = @source.index("{", map.begin) + 1
        while (entry = @source.match(/"([^"]+)"[ \t]*=[ \t]*\{/, cursor)) && entry.begin(0) < map.end
          close = matching_brace @source, entry.end(0) - 1
          entries[entry[1]] = entry.begin(0)..close
          cursor = close + 1
        end
        entries
      end

      def matching_brace(source, open)
        depth = 0
        index = open
        while index < source.length
          depth += 1 if source[index] == "{"
          depth -= 1 if source[index] == "}"
          return index if depth.zero?

          index += 1
        end
        raise "Unbalanced braces in #{path}"
      end

      def attributes_in(body)
        body.scan(%r{^[ \t]*(\w+)[ \t]*=[ \t]*((?:"(?:[^"\\]|\\.)*"|[^"#\n])+?)[ \t]*(?:(?:#|//).*)?$}).to_h
      end
    end
  end
end
