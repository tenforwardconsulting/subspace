#!/usr/bin/env ruby

require 'rubygems'
require 'commander'

require 'subspace'
require 'subspace/commands/base'
require 'subspace/commands/bootstrap'
require 'subspace/commands/configure'
require 'subspace/commands/exec'
require 'subspace/commands/init'
require 'subspace/commands/inventory'
require 'subspace/commands/override'
require 'subspace/commands/provision'
require 'subspace/commands/ssh'
require 'subspace/commands/secrets'
require 'subspace/commands/terraform'
require 'subspace/commands/maintain'
require 'subspace/commands/maintenance_mode.rb'
require 'subspace/commands/db_copy'
require 'subspace/commands/upgrade'

class Subspace::Cli
  include Commander::Methods
  # include whatever modules you need

  def run
    program :name, 'subspace'
    program :version, Subspace::VERSION
    program :description, 'Ansible-backed server provisioning tool for rails'

    unless system("which ansible > /dev/null")
      puts "*** Subspace depends on ansible being on your PATH. Please install it: https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html"
      exit 1
    end

    command :init do |c|
      c.syntax = 'subspace init'
      c.summary = 'Run without options to initialize subspace.'
      c.description = 'Some initialization routines can be run indiviaully, useful for upgrading'
      c.example 'init a new project with one default environment (default staging)', 'subspace init'
      c.example 'create a new fully automated production environment configuration', 'subspace init --terraform --env production'
      c.option '--ansible', 'initialize ansible for managing individual servers'
      c.option '--terraform', 'Initialize terraform for managing infrastructure'
      c.option '--env STRING', 'Initialize configuration for a new environment'
      c.option '--template [staging|production]', 'Use non-default template for this environment (default=staging)'
      c.when_called Subspace::Commands::Init
    end

    command :bootstrap do |c|
      c.syntax = 'subspace bootstrap [host]'
      c.summary = 'Install ansible requirements (python) and authorized_keys file'
      c.description = 'Ansible has very few dependencies, but python is one that is not installed by
      default on many linux images.  The bootstrap command will install python on a host as well as
      copy the authorized_keys file.  You will possibly need to type a password here.'
      c.option '--password', "Ask for a password instead of using ssh keys"
      c.option '--yum', "Use yum instead of apt to install python"
      c.option "-i", "--private-key PRIVATE-KEY", "Alias for private-key"
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

    command :tf do |c|
      c.syntax = 'subspace tf [environment]'
      c.summary = "Execute a terraform plan with the option to apply the plan after review"
      c.when_called Subspace::Commands::Terraform
    end

    command :ssh do |c|
      c.syntax = 'subspace ssh [options]'
      c.summary = 'ssh to the remote server as the administrative user'
      c.description = ''
      c.option '--user USER', "Use a different user (eg deploy).  Default is the ansible_user"
      Subspace::Commands::Ssh::PASS_THROUGH_PARAMS.each do |param_name|
        c.option "-#{param_name} #{param_name.upcase}", "Passed directly through to ssh command"
      end
      c.when_called Subspace::Commands::Ssh
    end

    command :exec do |c|
      c.syntax = 'subspace exec <host-spec> "<statement>" [options]'
      c.summary = 'execute <statement> on all hosts matching <host-spec>'
      c.description = ''
      c.option '--user USER', "Use a different user (eg deploy).  Default is the ansible_user"
      Subspace::Commands::Exec::PASS_THROUGH_PARAMS.each do |param_name|
        c.option "-#{param_name} #{param_name.upcase}", "Passed directly through to ssh command"
      end
      c.when_called Subspace::Commands::Exec
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

    command :secrets do |c, args|
      c.syntax = 'subspace secrets [environment]'
      c.summary = 'View or edit the encrypted variables for an environment'
      c.description = <<~EOS
        By default, this will simply show the variables for a specific environemnt.
        You can also edit variables, and we expect the functionality here to grow in the future.
        Running `subspace secrets development --create` is usually a great way to bootstrap a new development environment.
        EOS
      c.option '--edit', "Edit the variables instead of view"
      c.option '--create', "Create config/application.yml with the variables from the specified environment"
      c.when_called Subspace::Commands::Secrets
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

    command :maintenance_mode do |c, args|
      c.syntax = 'subspace maintenance_mode [options]'
      c.summary = 'Turns on or off maintenance mode'
      c.description = ''
      c.option "-i", "--private-key PRIVATE-KEY", "Alias for private-key"
      c.option "--on", "Turns on maintenance mode"
      c.option "--off", "Turns off maintenance mode"
      Subspace::Commands::MaintenanceMode::PASS_THROUGH_PARAMS.each do |param_name|
        c.option "--#{param_name} #{param_name.upcase}", "Passed directly through to ansible-playbook command"
      end
      c.when_called Subspace::Commands::MaintenanceMode
    end

    command :inventory do |c, args|
      c.syntax = 'subspace inventory <command>'
      c.summary = 'Manage, manipulate, and other useful inventory-related functions'
      c.description = <<~EOS
        Available inventory commands:

        capistrano - generate config/deploy/[env].rb.  Requires the --env option.
        list       - list the current inventory as understood by subspace.
        keyscan    - Update ~/.known_hosts with new host key fingerprints
        EOS
      c.option "--env ENVIRONMENT", "Optional: Limit function to a specific environment (aka group)"
      c.option "--rails-env ENVIRONMENT", "capistrano: the rails_env to set (default: --env)"
      c.option "--output PATH", "capistrano: write to PATH instead of stdout"
      c.when_called Subspace::Commands::Inventory
    end

    command :db_copy do |c|
      c.syntax = 'subspace db_copy --from [host] --to [host]'
      c.summary = 'Copy a postgres database from one host to another'
      c.description = <<~EOS
        Streams pg_dump | pg_restore directly between two servers over their private network,
        falling back to routing through this machine when they cannot reach each other.

        Refuses to copy from a host that is still serving traffic, or onto a database that
        already holds data, unless --force.
        EOS
      c.option '--from HOST', 'Source host, as named in inventory.yml'
      c.option '--to HOST', 'Destination host, as named in inventory.yml'
      c.option '--force', 'Copy anyway from a live source or onto a populated destination'
      c.option '--via-local', 'Route the dump through this machine instead of between the servers'
      c.when_called Subspace::Commands::DbCopy
    end

    command :upgrade do |c|
      c.syntax = 'subspace upgrade [environment] [phase]'
      c.summary = 'Replace an environment\'s servers with new ones built from a current AMI'
      c.description = <<~EOS
        Builds a new server beside the existing one, moves the environment onto it, and
        destroys the old one.  Each phase stops at a point where it is safe to walk away,
        because the deploy and the verification in between are yours to do.

        Phases, in order:

        --check               is this environment upgradeable?  (runs before every other phase)
        --revendor            re-vendor the terraform module at the version upgrades need
        --init                record the start of an upgrade
        --prepare             build, bootstrap and provision the new server
        --copy-db             open the maintenance window and copy the database across
        --cutover             move the elastic IP and close the maintenance window
        --finalize            dump the old database, then destroy the old server
        --status              where is this upgrade, and what is next?
        --abort               before a cutover: destroy the new server and forget the upgrade
        --close-instance-ssh  repair an interrupted cutover that left the servers able to ssh
        EOS
      c.example 'check whether production can be upgraded', 'subspace upgrade production --check'
      c.example 'build the replacement server', 'subspace upgrade production --prepare'
      c.option '--check', 'Verify this environment is upgradeable and stop'
      c.option '--revendor', 'Re-vendor the terraform module and print the migration steps'
      c.option '--init', 'Record the start of an upgrade in upgrade.yml'
      c.option '--status', 'Report the phase of the upgrade and the next step'
      c.option '--prepare', 'Build, bootstrap and provision the new server'
      c.option '--copy-db', 'Open the maintenance window and copy the database to the new server'
      c.option '--cutover', 'Move the elastic IP to the new server and end the maintenance window'
      c.option '--finalize', 'Destroy the old server'
      c.option '--abort', 'Destroy the new server (only before a cutover)'
      c.option '--close-instance-ssh', 'Close the temporary ssh path between the servers'
      c.option '--ubuntu-release RELEASE', "Ubuntu release to build the new server from (default: #{Subspace::Ami::DEFAULT_RELEASE})"
      c.option '--ami AMI', 'Use this AMI instead of looking one up'
      c.option '--via-local', 'Route the database copy through this machine'
      c.when_called Subspace::Commands::Upgrade
    end

    run!
  end
end

#MyApplication.new.run if $0 == __FILE__
