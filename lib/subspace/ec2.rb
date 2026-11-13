require 'subspace/aws_cli'
module Subspace
  module Ec2
    def self.elastic_ip_headroom(profile:, region:)
      quota = AwsCli.run("service-quotas", "get-service-quota", "--service-code", "ec2", "--quota-code", "L-0263D0A3",
        "--query", "Quota.Value", "--output", "text", profile: profile, region: region) do |stderr|
        # A quota that has never been adjusted has no applied value; 5 is the EC2-VPC default.
        next if stderr.include? "NoSuchResourceException"

        "aws service-quotas get-service-quota failed in profile #{profile}.  " \
          "Grant servicequotas:GetServiceQuota to that profile's user:\n#{stderr}"
      end
      in_use = AwsCli.run("ec2", "describe-addresses", "--query", "length(Addresses[?ServiceManaged==null])", "--output", "text",
        profile: profile, region: region) do |stderr|
        "aws ec2 describe-addresses failed in profile #{profile}:\n#{stderr}"
      end

      (quota || 5).to_f.to_i - in_use.to_i
    end
  end
end
