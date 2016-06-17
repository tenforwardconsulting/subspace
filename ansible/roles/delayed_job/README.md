# delayed_job Role

## Variables

### Optional

* `delayed_job_queues`
  The delayed job queues so the upstart script can start each one.
  If this is not set, then the upstart script will start delayed\_job without specifying any queue and it will run all of your jobs.
