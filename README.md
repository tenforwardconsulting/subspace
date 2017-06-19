# Subspace

Subspace is a rubygem meant to make provisioning as easy as Capistrano makes deploying.

http://tvtropes.org/pmwiki/pmwiki.php/Main/SubspaceAnsible

## Installation

First, install ansible (>2.0)

OSX:
  brew install ansible

linux:
  apt-get install ansible


Add this line to your application's Gemfile:

```ruby
gem 'subspace'
```

Or install it yourself as:

    $ gem install subspace

## Usage

* `subspace init`

Initialize the project for subspace. Creates `config/provision` with all
necessary files.

* `subspace provision <environment>`

Runs the playbook at `config/provision/<environment.yml>`.

* `subspace vars <environment> [--edit] [--create]`

Manage environment variables on different platforms.  The default action is simply to show the vars defined for an environemnt.  Pass --edit to edit them in the system editor.

The new system uses a file in `config/provision/templates/application.yml.template` that contains environment variables for all environments.  The configuration that is not secret is visible and version controlled, while the secrets are stored in the vault files for their environments. The default file created by `subspace init`  looks like this:

```
# These environment variables are applied to all environments, and can be secret or not

# This is secret and can be changed on all three environment easily by using subspace vars <env> --edit
SECRET_KEY_BASE: {{secret_key_base}}

#This is not secret, and is the same value for all environments
ENABLE_SOME_FEATURE: false

development:
  INSECURE_VARIABLE: "this isn't secret"

dev:
  INSECURE_VARIABLE: "but it changes"

production:
  INSECURE_VARIABLE: "on different servers"

```

Further, you can use the extremely command to create a local copy of `config/application.yml`

    # Create a local copy of config/application.yml with the secrets encrypted in vars/development.yml
    $ subspace vars development --create

This can get you up and running in development securely, the only thing you need to distribute to new team members is the vault password.

NOTE: application.yml should be in the `.gitignore`, since subspace creates a new version on the server and symlinks it on top of whatever is checked in.

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

## apache

The most important file for an apache install is the "project.conf" file that gets created in `sites-available` and symlinked to `sites-enabled`.  This is generated in a sensible way, but if you want to customize it you can do so by setting this variable to anything other than "project.conf":

    apache_project_conf: my_custom_configuration.conf

Then place my_custom_configuration.conf in config/provision/templates/my_custom_configuration.conf.  This will still get copied to the server as `sites-available/{project_name}.conf`

## collectd

## common

## delayed_job

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

Note that this role needs to be defined /before/ the apache role

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

## monit

## mysql

## mysql2_gem

## newrelic

## nginx

## papertrail

## passenger

## postgresql

  Sets up a postgres *server* - only use this on the database machine.

    backups_enabled: true
    s3_db_backup_bucket: disabled
    s3_db_backup_prefix: "{{project_name}}/{{rails_env}}"
    database_user: "{{project_name}}"

## puma

## rails

Provisions for a rails app.  This one is probably pretty important.

Default values (these are usually fine)

    database_pool: 5
    database_name: "{{project_name}}_{{rails_env}}"
    database_user: "{{project_name}}"
    job_queues:
      - default
      - mailers

Customize:

    rails_env: [whatever]

## redis

## ruby-common

Installs ruby on the machine.  YOu can set a version by picking off the download url and sha hash from ruby-lang.org

    ruby_version: ruby-2.4.1
    ruby_checksum: a330e10d5cb5e53b3a0078326c5731888bb55e32c4abfeb27d9e7f8e5d000250
    ruby_download_location: 'https://cache.ruby-lang.org/pub/ruby/2.4/ruby-2.4.1.tar.gz'


## sidekiq


## Other Internal Roles

Since ansible doesn't support versioning of roles, we cloned the role here so that it doesn't change unexpectedly.  We expect to update from upstream occasionally, please let us know if we're missing something we should have.

You should not include these roles directly in your subspace config files.  For example, instead of including `zenoamaro.postgresql`, simply include our `postgresql` role which depens on zenoamaro's role.

Thanks to the following repositories for making their roles available:
* https://github.com/zenoamaro/ansible-postgresql
* https://github.com/mtpereira/ansible-passenger


# Development

## Directory Structure

`ansible/roles`

Contains all of our custom roles. When the gem is installed and `subspace init`
is ran, the newly created `ansible.cfg` will be configured to look for these
roles.

`template`

Contains the template files that get copied over when `subspace init` is ran.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/tenforwardconsulting/subspace. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

# Roles and Variables

