{% if monit_installed is defined %}
begin
  # Needed for Puma 5 + puma-damon, but built in to Puma 4
  # https://github.com/kigster/puma-daemon
  # however not needed if we're using systemd which is the future
  require 'puma/daemon'
  daemonize
rescue LoadError => e
  daemonize
  # Puma 4 has `daemonize` built in
end
{% endif %}

# Change to match your CPU core count
workers {{puma_workers}}
# Min and Max threads per worker
threads {{puma_min_threads}}, {{puma_max_threads}}

app_dir = "/u/apps/{{project_name}}/current"
directory app_dir

rails_env = "{{rails_env}}"
environment rails_env

# Set up socket location
bind "tcp://127.0.0.1:9292"

# Logging
stdout_redirect "#{app_dir}/log/puma.stdout.log", "#{app_dir}/log/puma.stderr.log", true

pidfile "/u/apps/{{project_name}}/shared/tmp/pids/puma.pid"
state_path "/u/apps/{{project_name}}/shared/tmp/pids/puma.state"
activate_control_app

on_worker_boot do
  require "active_record"
  ActiveRecord::Base.connection.disconnect! rescue ActiveRecord::ConnectionNotEstablished
  ActiveRecord::Base.establish_connection(YAML.load_file("#{app_dir}/config/database.yml")[rails_env])
end

# Allow puma to be restarted by `rails restart` command.
plugin :tmp_restart
