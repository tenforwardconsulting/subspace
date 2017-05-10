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
    if @action == "create"
      init
      return
    end
    ansible_command "ansible-vault", @action, "vars/#{@environment}.yml"
  end

  def init
    if File.exists?("config/application.yml")
      answer = ask "config/application.yml already exists. Reply 'yes' to continue: [no] "
      abort unless answer == "yes"
    end
    src = File.join(project_path, "config/provision/application.yml.template")
    dest = File.join(project_path, "config/application.yml")
    vars_file = File.join(project_path, "config/provision/vars/#{@environment}.yml")
    extra_vars = "project_path=#{project_path} vars_file=#{vars_file}"
    ansible_command "ansible-playbook", File.join(playbook_dir, "local_template.yml"), "--extra-vars", extra_vars
    say "File created at config/application.yml with #{@environment} secrets"
    say "-------------------------------------------------------------------\n"

    system "cat", "config/application.yml"
  end
end
