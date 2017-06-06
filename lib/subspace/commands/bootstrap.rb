class Subspace::Commands::Bootstrap < Subspace::Commands::Base
  def initialize(args, options)
    @host_spec = args.first
    @ask_pass = options.password
    @yum = options.yum
    run
  end

  def run
    # ansible atlanta -m copy -a "src=/etc/hosts dest=/tmp/hosts"
    install_python
    ensure_ssh_dir
    copy_authorized_keys
  end

  private

  def ensure_ssh_dir
    cmd = ["ansible",
      @host_spec,
      "-m",
      "file",
      "-a",
      "path=/home/{{ansible_ssh_user}}/.ssh state=directory mode=0700",
      "-vvvv"
    ]
    bootstrap_command cmd
  end

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
    bootstrap_command cmd
  end

  def install_python
    update_ansible_cfg
    cmd = ["ansible",
      @host_spec,
      "-m",
      "raw",
      "-a",
      "test -e /usr/bin/python || (apt -y update && apt install -y python-minimal)",
      "--become",
      "-vvvv"
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
