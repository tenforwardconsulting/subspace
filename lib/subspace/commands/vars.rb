class Subspace::Commands::Vars < Subspace::Commands::Base
  def initialize(args, options)
    @environment = args.first
    @action = if options.edit
      "edit"
    elsif options.create
      "create"
    else
      "view"
    end

    run
  end

  def run
    case @action
    when "create"
      create_local
    when "view", "edit"
      ansible_command "ansible-vault", @action, "vars/#{@environment}.yml"
    else
      abort "Invalid vars command"
    end
  end

  def create_local
    if File.exists? File.join(project_path, "config/application.yml")
      answer = ask "config/application.yml already exists. Reply 'yes' to overwrite: [no] "
      abort unless answer == "yes"
    end
    src = application_yml_template
    dest = "config/application.yml"
    vars_file = File.join(project_path, "config/provision/vars/#{@environment}.yml")
    extra_vars = "project_path=#{project_path} vars_file=#{vars_file} src=#{src} dest=#{dest}"
    ansible_command "ansible-playbook", File.join(playbook_dir, "local_template.yml"), "--extra-vars", extra_vars
    say "File created at config/application.yml with #{@environment} secrets"
    say "-------------------------------------------------------------------\n"

    system "cat", "config/application.yml"
  end

  private

  def application_yml_template
    "config/provision/templates/application.yml.template"
  end

end
