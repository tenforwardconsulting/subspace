require 'open3'
module Subspace
  module Ec2
    def self.elastic_ip_headroom(profile:)
      quota = aws(profile, "service-quotas", "get-service-quota", "--service-code", "ec2", "--quota-code", "L-0263D0A3",
        "--query", "Quota.Value", "--output", "text") do |stderr|
        "aws service-quotas get-service-quota failed in profile #{profile}.  " \
          "Grant servicequotas:GetServiceQuota to that profile's user:\n#{stderr}"
      end
      in_use = aws(profile, "ec2", "describe-addresses", "--query", "length(Addresses)", "--output", "text") do |stderr|
        "aws ec2 describe-addresses failed in profile #{profile}:\n#{stderr}"
      end

      quota.to_f.to_i - in_use.to_i
    end

    def self.aws(profile, *args)
      stdout, stderr, status = Open3.capture3("aws", "--profile", profile, *args)
      abort yield(stderr) unless status.success?

      stdout
    end
  end
end
