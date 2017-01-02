require "subspace/version"

module Subspace
  def self.configure(&block)
    yield self.config
  end

  def self.config
    @config ||= Subspace::Configuration.new
  end
end
