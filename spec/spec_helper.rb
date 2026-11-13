$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'subspace'
require 'stringio'
require 'highline'

# A spec that misses a stub fails naming the binary, rather than running real terraform or aws.
ENV["PATH"] = "#{File.expand_path("bin", __dir__)}:#{ENV["PATH"]}"

RSpec.configure do |config|
  # An unstubbed ask would otherwise wait on the terminal.
  config.before do
    HighLine.default_instance = HighLine.new(StringIO.new, StringIO.new)
  end

  # abort and exit raise SystemExit, which RSpec deliberately does not rescue, so one stray
  # abort ends the whole run with "0 failures" instead of failing its example.
  config.around do |example|
    example.run
  rescue SystemExit => e
    raise "Unexpected exit (status #{e.status}): #{e.message}"
  end
end
