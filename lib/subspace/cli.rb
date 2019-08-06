#!/usr/bin/env ruby

require 'rubygems'
require 'commander'

require 'subspace'
require 'subspace/commands/base'
require 'subspace/commands/bootstrap'
require 'subspace/commands/configure'
require 'subspace/commands/init'
require 'subspace/commands/override'
require 'subspace/commands/provision'
require 'subspace/commands/ssh'
require 'subspace/commands/vars'
require 'subspace/commands/maintain'

class Subspace::Cli
  include Commander::Methods
  # include whatever modules you need

  def run
    program :name, 'subspace'
    program :version, Subspace::VERSION
    program :description, 'Ansible-backed server provisioning tool for rails'

    command :init do |c|
      c.syntax = 'subspace init [vars]'
      c.summary = 'Run without options to initialize subspace.'
      c.description = 'Some initialization routines can be run indiviaully, useful for upgrading'
      c.example 'init a new project', 'subspace init'
      c.example 'create the new style application.yml vars template', 'subspace init vars'
      c.when_called Subspace::Commands::Init
    end

    command :bootstrap do |c|
      c.syntax = 'subspace boostrap [host]'
      c.summary = 'Install ansible requirements (python) and authorized_keys file'
      c.description = 'Ansible has very few dependencies, but python is one that is not installed by
      default on many linux images.  The bootstrap command will install python on a host as well as
      copy the authorized_keys file.  You will possibly need to type a password here.'
      c.option '--password', "Ask for a password instead of using ssh keys"
      c.option '--yum', "Use yum instead of apt to install python"
      c.option "-i", "--private-key PRIVATE-KEY", "Alias for private-key"
      Subspace::Commands::Bootstrap::PASS_THROUGH_PARAMS.each do |param_name|
        c.option "--#{param_name} #{param_name.upcase}", "Passed directly through to ansible-playbook command"
      end
      c.when_called Subspace::Commands::Bootstrap
    end

    command :provision do |c|
      c.syntax = 'subspace provision [options]'
      c.summary = ''
      c.description = ''
      c.option "-i", "--private-key PRIVATE-KEY", "Alias for private-key"
      Subspace::Commands::Provision::PASS_THROUGH_PARAMS.each do |param_name|
        c.option "--#{param_name} #{param_name.upcase}", "Passed directly through to ansible-playbook command"
      end
      c.when_called Subspace::Commands::Provision
    end

    command :ssh do |c|
      c.syntax = 'subspace ssh [options]'
      c.summary = 'ssh to the remote server as the administrative user'
      c.description = ''
      c.option '--user USER', "Use a different user (eg deploy).  Default is the ansible_ssh_user"
      Subspace::Commands::Ssh::PASS_THROUGH_PARAMS.each do |param_name|
        c.option "-#{param_name} #{param_name.upcase}", "Passed directly through to ssh command"
      end
      c.when_called Subspace::Commands::Ssh
    end

    command :configure do |c, args|
      c.syntax = 'subspace configure'
      c.summary = "Regenerate all of the ansible configuration files. You don't normally need to run this."
      c.description = ''
      c.when_called Subspace::Commands::Configure
    end

    command :override do |c, args|
      c.syntax = 'subspace override [role]'
      c.summary = 'Override a role configuration by copying the configuration locally'
      c.description = 'Copies the default role configuration to config/provision/<role> where it can be modified.'
      c.when_called Subspace::Commands::Override
    end

    command :vars do |c, args|
      c.syntax = 'subspace vars [environment]'
      c.summary = 'View or edit the encrypted variables for an environment'
      c.description = """By default, this will simply show the variables for a specific environemnt.
                         You can also edit variables, and we expect the functionality here to grow in the future.
                         Running `subspace vars development --create` is usually a great way to bootstrap a new development environment."""
      c.option '--edit', "Edit the variables instead of view"
      c.option '--create', "Create config/application.yml with the variables from the specified environment"
      c.when_called Subspace::Commands::Vars
    end

    command :maintain do |c, args|
      c.syntax = 'subspace maintain [options]'
      c.summary = 'Runs provision with --tags=maintenance'
      c.description = ''
      c.option "-i", "--private-key PRIVATE-KEY", "Alias for private-key"
      Subspace::Commands::Maintain::PASS_THROUGH_PARAMS.each do |param_name|
        c.option "--#{param_name} #{param_name.upcase}", "Passed directly through to ansible-playbook command"
      end
      c.when_called Subspace::Commands::Maintain
    end

    run!
  end
end

#MyApplication.new.run if $0 == __FILE__
