# Subspace

[![Gem](https://img.shields.io/gem/v/subspace.svg)](https://rubygems.org/gems/subspace)

Subspace is a rubygem meant to make provisioning as easy as Capistrano makes deploying.

http://tvtropes.org/pmwiki/pmwiki.php/Main/SubspaceAnsible

It is powered by [Ansible](https://www.ansible.com/). Most of the roles require
you to [configure variables](https://docs.ansible.com/ansible/latest/user_guide/playbooks_variables.html) that the role uses.

## Installation

First, install ansible (>2.0)

OSX:

  brew install ansible

Linux:

  apt-get install ansible


Add this line to your application's Gemfile:

```ruby
gem 'subspace'
```

Or install it yourself as:

    $ gem install subspace

### Mitogen
Optionally, you can install a python/pip packaged called "Mitogen" which dramatically speeds up running ansible over ssh.  See [Here](https://github.com/mitogen-hq/mitogen/blob/master/docs/ansible_detailed.rst) for details.

    pip install mitogen

Subspace will try and detect if mitogen is present and use it can.  If mitogen causes problems (sometimes it can cause problems depending on the system versions, and particaularly when brand new versions of anible come up and it hasn't updated), you can disable it:

    DISABLE_MITOGEN=1 subspace provision env
## Usage

### `subspace init`

Initialize the project for subspace. Creates `config/subspace` with all
necessary files.

Subspace 3 supports terraform.  You will need to create an IAM user manually with administrative access to the target AWS environment for terraform.

### `subspace bootstrap <environment>`

Ensures the $HOME/.ssh directory is present and ensures python is installed.
Python is required to be installed on the remote server for the `provision`
command to work.

### `subspace provision <environment>`

Runs the playbook at `config/provision/<environment.yml>`.

You can pass certain options through to the `ansible-playbook` command. See [the
provision command](lib/subspace/commands/provision.rb) for the current list.

At the time of this writing, we pass through the `ansible-playbook` "tags" and
"start-at-task" options. The tags option is probably the most useful.

e.g. To run only the alienvault tasks (all of which have been tagged with the
'alienvault' tag): `subspace provision staging --tags=alienvault`

### `subspace maintain <environment>`

Runs the playbook at `config/provision/<environment.yml>` but only the tasks tagged with "maintenance".

You can pass certain options through to the `ansible-playbook` command. See [the
maintain command](lib/subspace/commands/maintain.rb) for the current list.

At the time of this writing, we pass through the `ansible-playbook` "limit" option.

e.g. To run only on the host "prod-web1": `subspace maintain production --limit=prod-web1`

### `subspace maintenance_mode <environment> --on`

This sets up nginx to return all requests as 503 and serve only the
static page at `/u/apps/{{project_name}}/current/public/maintenance.html`
which must be checked into your project and deployed to the server.

`--on` and `--off`, defaults to off.

Only works for hosts using the `nginx` role, but you can pass in your entire environment. Running it on worker servers won't hurt anything.

MUST be turned off manually by running `subspace maintenance_mode <environment> --off`, even a deploy will not disable maintenance mode.

#### Tagged roles

Role       | Tags                      | Comment
---------- | ----                      | -------
alienvault | alienvault                | All tasks in the alienvault role have been tagged 'alienvault'
common     | upgrade                   | runs apt-get update and apt-get upgrade
common     | authorized\_keys          | updates the authorized\_keys file for the deploy user
rails      | appyml                    |
monit      | monit                     | All tasks in the monit role have been tagged 'monit'

### `subspace vars <environment> [--edit] [--create]`

Manage environment variables on different platforms.  The default action is simply to show the vars defined for an environment.  Pass --edit to edit them in the system editor.

The new system uses a file in `config/provision/templates/application.yml.template` that contains environment variables for all environments.  The configuration that is not secret is visible and version controlled, while the secrets are stored in the vault files for their environments. The default file created by `subspace init`  looks like this:

```
# These environment variables are applied to all environments, and can be secret or not

# This is secret and can be changed on all three environment easily by using subspace vars <env> --edit
SECRET_KEY_BASE: {{secret_key_base}}

#This is not secret, and is the same value for all environments
ENABLE_SOME_FEATURE: false

development:
  INSECURE_VARIABLE: "this isn't secret"

staging:
  INSECURE_VARIABLE: "but it changes"

production:
  INSECURE_VARIABLE: "on different servers"

```

Further, you can use the extremely command to create a local copy of `config/application.yml`

    # Create a local copy of config/application.yml with the secrets encrypted in secrets/development.yml
    $ subspace vars development --create

This can get you up and running in development securely, the only thing you need to distribute to new team members is the vault password.  Grab it from a teammate and put it into `config/provision/.vault_pass`

NOTE: application.yml should be in the `.gitignore`, since subspace creates a new version on the server and symlinks it on top of whatever is checked in.

## Procedure for updating on projects

When subspace is updated, you should also update it for projects that use it. If subspace is locked to a specific version in the a project's gemfile, you'll need to update that to the new release number, first. Make sure this won't introduce any breaking changes by [looking at the changelog](https://github.com/tenforwardconsulting/subspace/blob/master/CHANGELOG.md).

* `bundle update subspace`

Then,

* `subspace provision production`

If you get an error saying you need a vault password file, you should be able to find it in 1Password. You might also need to update `ansible`.

You'll want to do this for each environment (ie: `subspace provision qa`, etc.). Best to start with staging and work your way up.

# Host configuration

We need to know some info about hosts, but not much.  See the files for details, it's mostly the hostname and the user that can administer the system, eg `ubuntu` on AWS/ubuntu, `ec2-user`, or even `root` (not recommended)

# Role Configuration

This is a description of all the roles that are included by installing subspace, along with their configuration.

## common

This role should almost always be there.  It ties a bunch of stuff together, runs apt-get update or yum upgrade, sets hostnames, and generally makes the server sane.

    project_name: my_project
    swap_space: 512M
    deploy_user: deploy

Note: we grant the deploy user limited sudo access to run `service xyz restart` and also add it to the `adm` group so it can view logs in `/var/log`.

# Roles

This is a description of all the roles that are included by installing subspace, along with their configuration.

## alienvault

Fixes CVEs on remote servers by installing updated versions of packages
depending on the operating system version.

Each CVE fix is tagged by the CVE name so updates can be targeted to a specific
vulnerability.

Variables: None

## apache

The most important file for an apache install is the "project.conf" file that gets created in `sites-available` and symlinked to `sites-enabled`.  This is generated in a sensible way, but if you want to customize it you can do so by setting this variable to anything other than "project.conf":

    apache_project_conf: my_custom_configuration.conf

Then place my_custom_configuration.conf in config/provision/templates/my_custom_configuration.conf.  This will still get copied to the server as `sites-available/{project_name}.conf`

Apache also support canonicalizing the domain now, so if you alwyas want to redirect to WWW for example, simply add a variable:

    canonical_domain: "www.example.com"

## collectd

Collectd is a super useful daemon that grabs and reports statistics about a server's health.  Adding this role will make your server start reporting to a [graphite](https://graphiteapp.org/) server that you specify, and you can make cool graphs and data feeds after that using something like [Grafana](https://grafana.com/)

    graphite_host: graphite.example.com
    graphite_port: "2003"

Aside from basic statistics like free memory, disk, load averages, etc, we have some custom things:

1. If Postgres and delayed job are installed, it will collect stats on number of outstanding delayed jobs.
  a. If you have pg on a different server or in RDS, you can set this manually:

    collectd_pgdj: true

2. If apache is installed, it will collect stats from the /server-status page
3. If nginx is installed, it will collect stats from the "status port"
4. (TODO) add something for pumas
5. (TODO) add something for sidekiq
6. If you're using our standard lograge format, you can enable lograge collection which will provide stats on request count and timers (db/view/total)

    rails_lograge: true


## common

## delayed_job

Install monitoring and automatic startup for delayed job workers via monit. You MUST set the `job_queues` variable as follows:

    job_queues:
      - default
      - mailers
      - exports

If you want to have multiple workers for a single queue, just add the queue name
multiple times:

    job_queues:
      - default
      - mailers
      - exports
      - exports
      - exports

Please note that by default, delayed job does not set a queue (eg it uses the "null" queue). You MUST also add an initializer to your rails app where you set the default queue name to "default" (or some other queue).  Otherwise, the named queue workers managed by this role will not process the "null" queue.

    # config/initializers/delayed_job.rb
    Delayed::Worker.default_queue_name = 'default'

Defaults:

    delayed_job_command: bin/delayed_job



## letsencrypt

By default, this creates a single certificate for every server alias/server name in the configuration file.
If you'd like more control over the certs created, you can define the variables `le_ssl_certs` as follows:

    le_ssl_certs:
      - cert_name: mycert
        domains:
          - mydomain.example.com
          - otherdomain.example.com
      - cert_name: othersite
        domains:
          - othersite.example.com

Note that this role needs to be included _before_ the webserver (apache or
nginx) role

## logrotate

Installs logrotate and lets you configure logs for automatic rotation.  Example config for rails:

    logrotate_scripts:
      - name: rails
        path: "/u/apps/{{project_name}}/shared/log/{{rails_env}}.log"
        options:
          - weekly
          - size 100M
          - missingok
          - compress
          - delaycompress
          - copytruncate

## memcache

Installs memcache on the server.  By default, memcache will only listen on localhost which needs to be changed if other servers needs to connect.

    # Default Value
    memcache_bind: "127.0.0.1"

    # bind to all interfaces
    memcache_bind: "0.0.0.0"

## monit

## mysql

## mysql2_gem

## newrelic

## newrelic-infra
This role will install the next-gen "Newrelic One" infrastructure agent which can perform a few different functions for newrelic.  The previous "newrelic" role is deprecated.

Variables:

    # Required, the newrelic license key you get after signing up.
    newrelic_license: "longhashthingyougetfromnewrelichere"
    # Optional - send logs to newrelic one's log aggregator.
    newrelic_logs:
      - name: rails-production
        path: /u/apps/blah/shared/log/production.log
      - name: nginx-error
        path: /var/log/nginx/error.log



## nginx-rails

Configures nginx to look at localhost:9292 for the socket/backend connection.  If you need to do fancy stuff you should simply override this role

    subspace override nginx-rails

defaults are here, we'll probably add more:

    client_max_body_size: 4G
    ssl_force_redirect: true
    default_server: true
    keepalive_timeout: 10
    extra_nginx_config: ""

Optional variables:

    asset_cors_allow_origin: Set this to set the Access-Control-Allow-Origin for
    everything in /assets.

    nginx_proxy_read_timeout: Set [proxy_read_timeout](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_read_timeout). This is in seconds. You probably only want to change this if using rack-timeout (although I may be wrong). If using rack-timeout, it should be slightly higher than the rack-timeout timeout. I'm doing 5 seconds higher, but that was arbitrarily chosen.

    ssl_force_redirect: redirect all HTTP traffic to HTTPS on the same host.  Defaults to true and only applies if ssl_enabled is also true.
    extra_nginx_config: anything else you want to configure in the main nginx config block, formatted like:
    extra_nginx_config: |
      proxy_http_version 1.1;
      chunked_transfer_encoding off;
      proxy_buffering off;
      proxy_cache off;

## nodejs

Used to install different versions of NodeJS. This uses NodeSource's apt repositories. You must define a variable called `nodejs_version` and choose a major version supported by NodeSource:

    nodejs_version: 14.x
    nodejs_version: 17.x
    nodejs_version: lts
    nodejs_version: current

The full list of distributions is here: https://github.com/nodesource/distributions#installation-instructions

## papertrail

## passenger

## postgresql

  Sets up a postgres *server* - only use this on the database machine.

    backups_enabled: true
    s3_db_backup_bucket: disabled
    s3_db_backup_prefix: "{{project_name}}/{{rails_env}}"
    database_user: "{{project_name}}"

## puma
Use the puma app server for your rails app.  Usually combined with nginx to server as a static file server and reverse proxy. 

**Prerequesites:**
  - add `gem puma` to your gemfile
  - add `config/puma/` to the `linked_dirs` config in capistrano's `deploy.rb`

This role will generate a reasonable `puma.rb` and configure it to be controlled by systemd. 

**Variables:**

    puma_workers: 1        # Puma process count (usually == vCPU count)
    puma_min_threads: 4    # Min threads/process
    puma_max_threads: 16   # Max threads/process

## rails

Provisions for a rails app.  This one is probably pretty important.

We no longer provider default values, so make sure to define all the following variables: 

    rails_env: production
    database_pool: 5
    database_name: "{{project_name}}_{{rails_env}}"
    database_user: "{{project_name}}"
    database_host: localhost
    database_adapter: postgresql
    database_password: # usually defined in the encrypted vault
    job_queues:
      - default
      - mailers

## redis

Installs redis on the server.

    # Change to * if you want this available everywhere instead of localhost
    redis_bind: 127.0.0.1

## resque

Install monitoring and automatic startup for resque workers via monit. You MUST set the `job_queues` variable as follows:

    job_queues:
      - default
      - mailers
      - exports

    redis_bind: "*"

## ruby-common

Installs ruby on the machine.  YOu can set a version by picking off the download url and sha hash from ruby-lang.org

    ruby_version: ruby-2.4.1
    ruby_checksum: a330e10d5cb5e53b3a0078326c5731888bb55e32c4abfeb27d9e7f8e5d000250
    ruby_download_location: 'https://cache.ruby-lang.org/pub/ruby/2.4/ruby-2.4.1.tar.gz'
    bundler_version: 2.0.1


## sidekiq

This will install a monit script that keeps sidekiq running.  We spawn one sidekiq instance that manages as many queues as you need.  Varaibles of note:

    # Process these queues on this server
    job_queues:
      - default
      - mailers

    # Number of sidekiq *processes* to run
    sidekiq_workers: 1

* Note that as of v0.4.13, we now also add a unique job queue for each host with its hostname.  This is handy if you need to assign a job to a specific host.  In general you should use named queues, but occasionally this is useful and there's no harm in having it there unused.

Sidekiq uses redis by default, and rails connects to a redis running on localhost by default.  However, this role does not depend on redis since in production it's likely redis will be running elsewhere.  If you're provisioning a standalone server, make sure to include the redis role.


## Other Internal Roles

Since ansible doesn't support versioning of roles, we cloned the role here so that it doesn't change unexpectedly.  We expect to update from upstream occasionally, please let us know if we're missing something we should have.

You should not include these roles directly in your subspace config files.  For example, instead of including `zenoamaro.postgresql`, simply include our `postgresql` role which depens on zenoamaro's role.

Thanks to the following repositories for making their roles available:
* https://github.com/zenoamaro/ansible-postgresql
* https://github.com/mtpereira/ansible-passenger


# Mitogen

In order to dramatically speed up ansible, you can install Mitogen: https://github.com/mitogen-hq/mitogen/blob/master/docs/ansible_detailed.rst

    pip install -g mitogen

Subspace will automatically detect this and update your ansible.cfg file so it is blazing fast.


## Directory Structure

`ansible/roles`

Contains all of our custom roles. When the gem is installed and `subspace init`
is ran, the newly created `ansible.cfg` will be configured to look for these
roles.

`template`

Contains the template files that get copied over when `subspace init` is ran.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version:

  1. update the version number in `version.rb`
  2. `gem build subspace.gemspec`
  3. `gem push subspace-x.y.z.gem`

This will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/tenforwardconsulting/subspace. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

# Roles and Variables
