require 'fileutils'
require 'erb'
require 'securerandom'
class Subspace::Commands::Init < Subspace::Commands::Base
  def initialize(args, options)
    options.default env: "staging"

    @env = options.env

    if options.ansibe.nil? && options.terraform.nil?
      # They didn't pass in any options (subspace init) so just do both
      options.ansible = true
      options.terraform = true
    end
    @init_ansible = options.ansible
    @init_terraform = options.terraform
    run
  end

  def run
    if File.exists? dest_dir
      answer = ask "Subspace appears to be initialized.  Reply 'yes' to continue anyway: [no] "
      abort unless answer.chomp == "yes"
    else
      FileUtils.mkdir_p dest_dir
    end

    init_pemfile
    init_ansible if @init_ansible
    init_terraform if @init_terraform

    puts """
    1. Inspect key config files:
      - config/subspace/terraform/#{@env}/main.tf     # Main terraform file
      - config/subspace/#{@env}.yml                   # Main ansible playbook
      - config/subspace/group_vars                    # Ansible configuration options
      - config/subspace/inventory.yml                 # Server Inventory
      - config/subspace/templates/authorized_keys     # SSH Authorized Keys
      - config/subspace/templates/application.yml     # Application Environment variables

    2. create cloud infrastructure with terraform:

      subspace tf #{@env}`

    3. Bootstrap the new server

      subspace boostrap staging1

    4. Inspect new environment
      - ensure the correct roles are present in #{@env}.yml
      - Check ansible configuration variables in group_vars/#{@env}

    4. Provision the new servers with ansible:

      subspace provision stagingservers

  """

  end

  private

  def init_pemfile
    pem = File.join dest_dir, "subspace.pem"
    if File.exist?(pem)
      say "Existing SSH Keypair exists.  Skipping keygen."
    else
      say "Creating SSH Keypair in #{pem}"
      `ssh-keygen -t rsa -f #{pem}`
    end
  end

  def init_ansible
    FileUtils.mkdir_p File.join dest_dir, "group_vars"
    FileUtils.mkdir_p File.join dest_dir, "secrets"
    FileUtils.mkdir_p File.join dest_dir, "roles"
    FileUtils.mkdir_p File.join dest_dir, "templates"

    copy ".gitignore"
    template "ansible.cfg"
    template "group_vars/all"
    template "inventory.yml"
    template "templates/authorized_keys"

    create_vault_pass
    @hostname = hostname(@env)
    create_secrets_for @env
    template "group_vars/template", "group_vars/#{@env}servers"
    template "playbook.yml", "#{@env}servers.yml"

    create_secrets_for "development" #TODO rename to local?
    init_appyml
  end

  def init_terraform
    FileUtils.mkdir_p File.join dest_dir, "terraform", @env

    FileUtils.ln_sf File.join(gem_path, 'terraform', 'modules'), File.join(dest_dir, "terraform", ".subspace-tf-modules")
    template "terraform/template/main.tf", "terraform/#{@env}/main.tf"
    copy "terraform/.gitignore"
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

  def create_secrets_for(env)
    template "secrets/template", "secrets/#{env}.yml"
    Dir.chdir dest_dir do
      `ansible-vault encrypt secrets/#{env}.yml`
    end
  end

  def init_appyml
    copy "templates/application.yml.template"
  end
end
