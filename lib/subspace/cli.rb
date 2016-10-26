#!/usr/bin/env ruby

require 'rubygems'
require 'commander'

require 'subspace/commands/init'
require 'subspace/commands/provision'
require 'subspace/commands/ssh'

class Subspace::Cli
  include Commander::Methods
  # include whatever modules you need

  def run
    program :name, 'subspace'
    program :version, '0.0.1'
    program :description, 'Ansible-backed server provisioning tool for rails'

    command :init do |c|
      c.syntax = 'subspace init [options]'
      c.summary = ''
      c.description = ''
      c.example 'description', 'command example'
      c.option '--some-switch', 'Some switch that does something'
      c.when_called Subspace::Commands::Init
    end

    command :provision do |c|
      c.syntax = 'subspace provision [options]'
      c.summary = ''
      c.description = ''
      c.example 'description', 'command example'
      c.option '--some-switch', 'Some switch that does something'
      c.when_called Subspace::Commands::Provision
    end

    command :ssh do |c|
      c.syntax = 'subspace ssh [options]'
      c.summary = 'ssh to the remote server as the administrative user'
      c.description = ''
      c.when_called Subspace::Commands::Ssh
    end

    run!
  end
end

#MyApplication.new.run if $0 == __FILE__
