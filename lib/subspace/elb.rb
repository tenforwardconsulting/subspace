require 'json'
require 'subspace/aws_cli'
module Subspace
  module Elb
    def self.target_health(target_group_arn, profile:, region:)
      stdout = AwsCli.run("elbv2", "describe-target-health", "--target-group-arn", target_group_arn, "--output", "json",
        profile: profile, region: region) do |stderr|
        "aws elbv2 describe-target-health failed in profile #{profile}:\n#{stderr}"
      end

      JSON.parse(stdout).fetch("TargetHealthDescriptions").to_h do |description|
        [description.fetch("Target").fetch("Id"), description.fetch("TargetHealth").fetch("State")]
      end
    end
  end
end
