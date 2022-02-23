class Subspace::Commands::Bootstrap < Subspace::Commands::Base
  PASS_THROUGH_PARAMS = ["private-key"]

  def initialize(args, options)
    @host_spec = args.first
    @options = options
    @ask_pass = options.password
    @yum = options.yum
    run
  end

  def run
    # ansible atlanta -m copy -a "src=/etc/hosts dest=/tmp/hosts"
    install_python
    ensure_ssh_dir
  end

  private

  def ensure_ssh_dir
    cmd = ["ansible",
      @host_spec,
      "--private-key",
      "config/subspace/subspace.pem",
      "-v",
      "-m",
      "file",
      "-a",
      "path=/home/{{ansible_user}}/.ssh state=directory mode=0700",
    ]
    cmd = cmd | pass_through_params
    bootstrap_command cmd
  end

  def install_python
    update_ansible_cfg
    cmd = ["ansible",
      @host_spec,
      "--private-key",
      "config/subspace/subspace.pem",
      "-m",
      "raw",
      "-a",
      "test -e /usr/bin/python || (apt -y update && apt install -y python-minimal)",
      "--become"
    ]
    cmd = cmd | pass_through_params
    bootstrap_command cmd
  end

  def bootstrap_command(cmd)
    if @ask_pass
      cmd.push("--ask-pass")
    end
    ansible_command *cmd
  end
end
