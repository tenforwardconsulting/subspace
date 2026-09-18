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
      end

      def module_name
        @source[/^module\s+"?([\w-]+)"?\s*\{/, 1] or raise "No module block found in #{path}"
      end

      def instances
        body = map_body
        entries = {}
        cursor = 0
        while (entry = body.match(/"([^"]+)"[ \t]*=[ \t]*\{/, cursor))
          open = entry.end(0) - 1
          close = matching_brace body, open
          entries[entry[1]] = attributes_in body[(open + 1)...close]
          cursor = close + 1
        end
        entries
      end

      def hostname_for(key)
        self.class.unquote instances.fetch(key)["hostname"]
      end

      def add_instance(key, attributes)
        raise "Slot #{key} is already defined in #{path}" if instances.key? key

        write_instances instances.merge(key => attributes)
      end

      def remove_instance(key)
        raise "There is no slot #{key} in #{path}" unless instances.key? key

        write_instances instances.reject { |slot, _| slot == key }
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

      def write_instances(entries)
        indent = @source[/^([ \t]*)instances[ \t]*=/, 1]
        width = entries.values.flat_map(&:keys).map(&:length).max
        lines = ["#{indent}instances = {"]
        entries.sort_by { |key, _| key.to_i }.each do |key, attributes|
          lines << %(#{indent}  "#{key}" = {)
          attributes.each { |name, literal| lines << "#{indent}    #{name.ljust(width)} = #{literal}" }
          lines << "#{indent}  }"
        end
        lines << "#{indent}}"
        @source[map_range] = lines.join("\n")
      end

      def map_range
        match = @source.match(/^[ \t]*instances[ \t]*=[ \t]*\{/)
        raise "#{path} has no `instances` map.  Is its terraform module at least v2.0.0?" if match.nil?

        (match.begin(0)..matching_brace(@source, match.end(0) - 1))
      end

      def map_body
        range = map_range
        open = @source.index "{", range.begin
        @source[(open + 1)...range.end]
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
        body.scan(/^[ \t]*(\w+)[ \t]*=[ \t]*(.+?)[ \t]*$/).to_h
      end
    end
  end
end
