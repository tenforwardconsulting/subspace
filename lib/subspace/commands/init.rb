require 'fileutils'
require 'erb'
require 'subspace/commands/base'
puts "Required init"
class Subspace::Commands::Init < Subspace::Commands::Base
  @@provision_templatedir = File.join(File.dirname(__FILE__), '..', 'template', 'provision')
  @@dest_dir = "config/provision"

  def initialize(args, options)
    run
  end

  def run
    FileUtils.mkdir_p File.join @@dest_dir, "group_vars"
    FileUtils.mkdir_p File.join @@dest_dir, "host_vars"
    FileUtils.mkdir_p File.join @@dest_dir, "vars"

    copy ".gitignore"
    template "ansible.cfg"
    template "hosts"
    template "group_vars/all"
    create_vault_pass
    environments.each do |env|
      @env = env
      @hostname = hostname(env)
      template "group_vars/template", "group_vars/#{env}"
      template "host_vars/template", "host_vars/#{env}"
      create_vars_file_for_env env
      template "playbook.yml", "#{env}.yml"
    end

    puts """
    1. Create a server.

    2. Set your server's location:

      vim config/provision/host_vars/production
      vim config/provision/host_vars/dev

    3. Set up your authorized_keys:

      vim config/provision/authorized_keys

    4. Then provision your server:

      cd config/provision && ansible-playbook dev.yml

  """

  end

  private

  def project_name
    File.basename(Dir.pwd)
  end

  def copy(src, dest = nil)
    dest ||= src
    FileUtils.cp File.join(@@provision_templatedir, src), File.join(@@dest_dir, dest)
  end

  def environments
    %w(production dev)
  end

  def hostname(env)
    "#{project_name.gsub('_', '-')}-#{env}"
  end

  def create_vault_pass
    File.write File.join(@@dest_dir, ".vault_pass"), SecureRandom.base64
  end

  def create_vars_file_for_env(env)
    template "vars/template", "vars/#{env}.yml"
    Dir.chdir @@dest_dir do
      `ansible-vault encrypt vars/#{env}.yml`
    end
  end
end
