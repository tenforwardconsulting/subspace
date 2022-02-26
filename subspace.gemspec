# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'subspace/version'

Gem::Specification.new do |spec|
  spec.name          = "subspace"
  spec.version       = Subspace::VERSION
  spec.authors       = ["Brian Samson"]
  spec.email         = ["brian@tenforwardconsulting.com"]

  spec.summary       = %q{Ansible-based server provisioning for rails projects}
  spec.description   = %q{WIP -- don't use this :)}
  spec.homepage      = "https://github.com/tenforwardconsulting/subspace"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "https://rubygems.org"
  else
    raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   << "subspace"
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 2.1"
  spec.add_development_dependency "rake", "~> 12.3.3"
  spec.add_development_dependency "rspec", "~> 3.0"

  spec.add_runtime_dependency "commander", "~>4.2"
  spec.add_runtime_dependency "figaro", "~>1.0"
end
