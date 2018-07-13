# Changelog

This is a [changelog](https://keepachangelog.com/en/0.3.0/).

This project attempts to follow [semantic versioning](https://semver.org/)

## Unreleased

* features
  * The nginx collectd configuration now reports number of errors (500-503),
    timeouts (504) and successes (200, 302, 304)

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
