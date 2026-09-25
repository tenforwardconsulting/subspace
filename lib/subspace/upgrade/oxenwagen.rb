module Subspace
  module Upgrade
    # N web servers behind an ALB, with RDS and ElastiCache alongside.  An OS upgrade here
    # is a rolling replace of the web and worker instances with no data migration and no
    # maintenance window, so it shares almost nothing with the workhorse cutover.
    # Not built yet; see docs/server-upgrade-plan.md section 7.
    class Oxenwagen < Base
      TEMPLATE = "oxenwagen"

      %i[check status init launch provision copy_db cutover finalize abort_upgrade close_instance_ssh revendor].each do |phase|
        define_method phase do
          abort "`subspace upgrade` does not support oxenwagen environments yet.  Upgrade #{env} by hand."
        end
      end
    end
  end
end
