require 'json'
require 'open3'
module Subspace
  module Upgrade
    module Elb
      def self.target_health(target_group_arn, profile:)
        stdout, stderr, status = Open3.capture3("aws", "--profile", profile, "elbv2", "describe-target-health",
          "--target-group-arn", target_group_arn, "--output", "json")
        abort "aws elbv2 describe-target-health failed in profile #{profile}:\n#{stderr}" unless status.success?

        JSON.parse(stdout).fetch("TargetHealthDescriptions").to_h do |description|
          [description.fetch("Target").fetch("Id"), description.fetch("TargetHealth").fetch("State")]
        end
      end
    end
  end
end
