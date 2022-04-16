class Subspace::Commands::Bootstrap < Subspace::Commands::Base

  def initialize(args, options)
    @host_spec = args.first
    @options = options
    @ask_pass = options.password
    @yum = options.yum
    run
  end

  def run
    # ansible atlanta -m copy -a "src=/etc/hosts dest=/tmp/hosts"
    hosts = inventory.find_hosts!(@host_spec)
    update_ansible_cfg
    hosts.each do |host|
      say "Bootstapping #{host.vars["hostname"]}..."
      learn_host(host)
      install_python(host)
    end
  end

  private

  def learn_host(host)
    system "ssh-keygen -R #{host.vars["ansible_host"]}"
    system "ssh-keyscan -H #{host.vars["ansible_host"]} >> ~/.ssh/known_hosts"
  end

  def install_python(host)
    cmd = ["ansible",
      host.name,
      "--private-key",
      "config/subspace/subspace.pem",
      "-m",
      "raw",
      "-a",
      "test -e /usr/bin/python3 || (apt -y update && apt install -y python3)",
      "--become"
    ]
    bootstrap_command cmd
  end

  def bootstrap_command(cmd)
    if @ask_pass
      cmd.push("--ask-pass")
    end
    ansible_command *cmd
  end
end
