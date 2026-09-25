require 'fileutils'
require 'erb'
require 'securerandom'
require 'subspace/upgrade'
class Subspace::Commands::Init < Subspace::Commands::Base
  TERRAFORM_MODULES = {
    "workhorse" => {
      repo: "https://github.com/tenforwardconsulting/terraform-subspace-workhorse.git",
      ref: "v2.0.0"
    },
    "oxenwagen" => {
      repo: "https://github.com/tenforwardconsulting/terraform-subspace-oxenwagen.git",
      ref: "v2.4.1"
    }
  }

  def initialize(args, options)
    options.default env: "dev"

    @env = options.env
    @template = options.template

    if options.ansibe.nil? && options.terraform.nil?
      # They didn't pass in any options (subspace init) so just do both
      options.ansible = true
      options.terraform = true
    end

    if @template.nil? && options.terraform == true
      answer = ask "What template/server configuration would you like to use? e.g. 'workhorse' or 'oxenwagen'"
      @template = answer
    end

    @init_ansible = options.ansible
    @init_terraform = options.terraform
    run
  end

  def run
    if File.exist? dest_dir
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
      - config/subspace/terraform/#{@env}/modules     # Vendored terraform module
      - config/subspace/#{@env}.yml                   # Main ansible playbook
      - config/subspace/group_vars                    # Ansible configuration options
      - config/subspace/inventory.yml                 # Server Inventory
      - config/subspace/templates/authorized_keys     # SSH Authorized Keys
      - config/subspace/templates/application.yml     # Application Environment variables

    2. create cloud infrastructure with terraform:

      subspace tf #{@env}

    3. Bootstrap the new server

      subspace bootstrap #{@env}1

    4. Inspect new environment
      - ensure the correct roles are present in #{@env}.yml
      - Check ansible configuration variables in group_vars/#{@env}

    5. Provision the new servers with ansible:

      subspace provision #{@env}

    !!MAKE SURE YOU PUT config/subspace/subspace.pem in 1Password!!
    !!If you added an SSH Key Passphrase during that step, also save it in 1Password!!

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
    template "group_vars/template", "group_vars/#{@env}"
    template "playbook.yml", "#{@env}.yml"

    create_secrets_for "development" #TODO rename to local?
    init_appyml
  end

  def init_terraform
    Subspace::Commands::Terraform.ensure_terraform
    FileUtils.mkdir_p File.join dest_dir, "terraform", @env

    set_latest_ami
    @module_source = vendor_terraform_module
    template "terraform/template/main-#{@template}.tf", "terraform/#{@env}/main.tf"
    copy "terraform/.gitignore"
  end

  def vendor_terraform_module
    mod = TERRAFORM_MODULES[@template]
    if mod.nil?
      say "Unknown template '#{@template}'.  No module to vendor."
      return nil
    end

    dest = File.join dest_dir, "terraform", @env, "modules", @template
    if Dir.exist? dest
      say "#{dest} already exists.  Skipping clone."
      return "./modules/#{@template}"
    end

    say "Cloning #{mod[:repo]} (#{mod[:ref]}) into #{dest}"
    FileUtils.mkdir_p File.dirname(dest)
    unless system("git", "clone", "--depth", "1", "--branch", mod[:ref], mod[:repo], dest)
      abort "Failed to clone #{mod[:repo]}"
    end
    FileUtils.rm_rf File.join(dest, ".git")
    FileUtils.rm_f File.join(dest, ".gitmodules")
    Subspace::Upgrade::ModuleManifest.write dest, template: @template, repo: mod[:repo], ref: mod[:ref]

    "./modules/#{@template}"
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

  def set_latest_ami
    @latest_ami = Subspace::Ami.latest release: Subspace::Ami::DEFAULT_RELEASE,
      profile: "subspace-#{project_name}"
  end
end
