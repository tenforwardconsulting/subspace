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
      "-m",
      "file",
      "-a",
      "path=/home/{{ansible_ssh_user}}/.ssh state=directory mode=0700",
      "-vvvv"
    ]
    cmd = add_pass_through_params cmd
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
    cmd = add_pass_through_params cmd
    bootstrap_command cmd
  end

  def bootstrap_command(cmd)
    if @ask_pass
      cmd.push("--ask-pass")
    end
    ansible_command *cmd
  end

  def add_pass_through_params(cmd)
    PASS_THROUGH_PARAMS.each do |param_name|
      x = param_name.split('-')[1..-1].map(&:upcase).join('_')
      hash_key = (param_name.gsub('-', '_') + (x == '' ? '' : "_#{x}")).to_sym
      value = @options.__hash__[hash_key]
      if value
        cmd += ["--#{param_name}", value]
      end
    end
    cmd
  end
end
