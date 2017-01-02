#!/bin/bash
# Julius Zaromskis
# Modified by Brian Samson to support postgres instead
# Backup rotation

# Storage folder where to move backup files
# Must contain backup.monthly backup.weekly backup.daily folders
storage=/u/apps/{{project_name}}/shared/db/backups
bucket="{{s3_db_backup_bucket}}"
prefix="{{s3_db_backup_prefix}}"

# Destination file names
date_hourly=`date +"%Y%m%d%H%M"`
filename="$date_hourly.dump"
#date_weekly=`date +"%V sav. %m-%Y"`
#date_monthly=`date +"%m-%Y"`

month_day=`date +"%d"`
week_day=`date +"%u"`
hour=`date +"%H"`


if [ "$hour" -eq 0 ] ; then
  # at midnight we do the daily logic
  # On first month day do
  if [ "$month_day" -eq 1 ] ; then
    destination=backup.monthly/$filename
  else
    # On saturdays do
    if [ "$week_day" -eq 6 ] ; then
      destination=backup.weekly/$filename
    else
      destination=backup.daily/$filename
    fi
  fi
else
  # Every other hour just put it in the hourly
  destination=backup.hourly/$filename
fi

if [ "$bucket" != "disabled" ] ; then
  if [ -f "$storage/latest.dump" ] ; then
    if [ -f "$storage/latest-old.dump" ] ; then
      rm "$storage/latest-old.dump"
    fi
    mv "$storage/latest.dump" "$storage/latest-old.dump"
  fi

  $(PGPASSWORD={{database_password}} pg_dump --verbose -Fc --host=localhost --username={{database_user}} --file $storage/latest.dump {{database_name}})

  curl -XPUT -T "$storage/latest.dump" -H "Host: $bucket.s3.amazonaws.com" https://$bucket.s3.amazonaws.com/$prefix/$destination
else
  #destination is set so actually do the backup
  $(PGPASSWORD={{database_password}} pg_dump --verbose -Fc --host=localhost --username={{database_user}} --file $storage/$destination {{database_name}})

  # then clean old ones
  # hourly - for 48 hours
  find $storage/backup.hourly/ -mmin +2880 -exec rm -rv {} \;
  # daily - keep for 14 days
  find $storage/backup.daily/ -mtime +14 -exec rm -rv {} \;
  # weekly - keep for 60 days
  find $storage/backup.weekly/ -mtime +60 -exec rm -rv {} \;
  # monthly - keep for 300 days
  find $storage/backup.monthly/ -mtime +300 -exec rm -rv {} \;
fi
