class Subspace::Commands::Bootstrap < Subspace::Commands::Base
  def initialize(args, options)
    @host_spec = args.first
    @ask_pass = options.password
    @yum = options.yum
    run
  end

  def run
    # ansible atlanta -m copy -a "src=/etc/hosts dest=/tmp/hosts"
    copy_authorized_keys
    install_python
  end

  private

  def copy_authorized_keys
    # -m file -a "dest=/srv/foo/a.txt mode=600"
    cmd = ["ansible",
      @host_spec,
      "-m",
      "copy",
      "-a",
      "src=authorized_keys dest=/home/{{ansible_ssh_user}}/.ssh/authorized_keys mode=600",
      "-vvvv"
    ]
    if @ask_pass
      cmd.push("--ask-pass")
    end
    ansible_command *cmd
  end

  def install_python
    update_ansible_cfg
    cmd = ["ansible",
      @host_spec,
      "-m",
      @yum ? "yum" : "apt",
      "-a",
      "name=python state=present",
      "--become",
      "-vvvv"
    ]
    ansible_command *cmd
  end

end
