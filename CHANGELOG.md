# Changelog

This is a [changelog](https://keepachangelog.com/en/0.3.0/).

This project attempts to follow [semantic versioning](https://semver.org/)

## Unreleased

* _nada_

## 1.0.0 - 2018-08-15

No breaking changes from 0.6.17 to 1.0.0, but decided it's time for version
1.0.0 to be out.

* enhancements
  * Tag tasks in the alienvault and monit roles such that all tasks are tagged
    with the role name.
  * Make tags 'upgrade' for doing apt-get update and upgrade and
    'authorized\_keys' for setting deploy user's authorized\_keys in the common
    role.
  * Make tag 'appyml' for the task to upload application.yml in the rails role.

* features
  * Add ability to pass certain options through `subspace provision` to
    `ansible-playbook`. These are: tags, start-at-task

## 0.6.17 - 2018-08-14

* bug fixes
  * Pin monit version to 1:5.16-2 due to a [bug](https://bugs.launchpad.net/ubuntu/+source/monit/+bug/1786910)

## 0.6.16 - 2018-07-27

* bug fix
  * Remove /cable location entry for nginx-rails config file

## 0.6.15 - 2018-07-17

* features
  * The nginx collectd configuration now reports number of errors (500-503),
    timeouts (504) and successes (200, 302, 304)
  * Add alienvault role that can configure ubuntu to send syslog to a sensor.
  * nginx-rails role: Add ability to set nginx's `proxy_read_timeout`.

* bug fixes
  * Don't have rails role install yarn -- it's not needed by default, and if the
    project does need it, it should explicitly use the yarn role.

## 0.5.15 - 2018-06-15

* bug fixes
  * Update rails and logrotate modules to work with Python 3

## 0.5.14 - 2018-06-15

* bug fixes
  * Fix Postgres role's backup script to include AWS ACL header that fixes
    bucket object permissions.

* features
  * Add yarn and nodejs roles.

## Version - Date

* breaking changes
  * enhancement A
  * enhancement B

* deprecations
  * deprecation A
  * deprecation B

* bug fixes
  * bug fix A
  * bug fix B

* enhancements
  * enhancement A
  * enhancement B

* features
  * feature A
  * feature B
