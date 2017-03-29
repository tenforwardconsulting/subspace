require "subspace/version"
require "subspace/configuration"

module Subspace
  def self.configure(&block)
    yield self.config
  end

  def self.config
    @config ||= Subspace::Configuration.new
  end
end
