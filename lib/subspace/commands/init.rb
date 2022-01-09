require 'fileutils'
require 'erb'
require 'securerandom'
class Subspace::Commands::Init < Subspace::Commands::Base
  def initialize(args, options)
    options.default env: "dev"
    @env = options[:env]

    if !options[:ansible] && !options[:terraform]
      # They didn't pass in any options (subspace init) so just do both
      options[:ansibe] = options[:terraform] = true
    end

    if options[:ansible]
      init_ansible
    end

    if options[:terraform]
      init_terraform
    end
  end

  def run
    if File.exists? dest_dir
      answer = ask "Subspace appears to be initialized.  Reply 'yes' to continue anyway: [no] "
      abort unless answer.chomp == "yes"
    end

    init_ansible

    puts """
    1. Create a server.

    2. Set your server's location:

      vim config/subspace/inventory.yml

    3. Set up your authorized_keys:

      vim config/provision/authorized_keys

    4. Then provision your server:

      subspace provision dev

  """

  end

  private

  def init_ansible
    FileUtils.mkdir_p File.join dest_dir, "group_vars"
    FileUtils.mkdir_p File.join dest_dir, "vars"
    FileUtils.mkdir_p File.join dest_dir, "roles"

    copy ".gitignore"
    template "ansible.cfg"
    template "inventory.yml", "inventory.#{@env}.yml"
    template "group_vars/all"

    create_vault_pass
    @hostname = hostname(@env)
    template "group_vars/template", "group_vars/#{@env}"
    create_vars_file_for_env @env
    template "playbook.yml", "#{@env}.yml"

    create_vars_file_for_env "development" #TODO rename to local
    init_appyml
  end

  def init_terraform

  end

  def project_name
    File.basename(Dir.pwd)
  end

  def hostname(env)
    "#{project_name.gsub('_', '-')}-#{env}"
  end

  def create_vault_pass
    if File.exist? File.join(dest_dir, ".vault_pass")
      say ".vault_pass already exists.  Skipping..."
    else
      File.write File.join(dest_dir, ".vault_pass"), SecureRandom.base64
    end
  end

  def create_vars_file_for_env(env)
    template "vars/template", "vars/#{env}.yml"
    Dir.chdir dest_dir do
      `ansible-vault encrypt vars/#{env}.yml`
    end
  end

  def init_appyml
    FileUtils.mkdir_p File.join dest_dir, "templates"
    copy "templates/application.yml.template"
  end
end
