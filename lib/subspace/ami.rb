require 'subspace/aws_cli'
module Subspace
  module Ami
    DEFAULT_RELEASE = "resolute"

    def self.latest(release:, profile:, region:)
      pattern = "ubuntu/images/hvm-ssd-gp3/ubuntu-#{release}-*-amd64-server-*"
      stdout = AwsCli.run("ec2", "describe-images",
        "--owners", "099720109477",
        "--filters", "Name=name,Values=#{pattern}",
        "--query", "Images[*].[ImageId,CreationDate]", "--output", "text",
        profile: profile, region: region) do |stderr|
        "aws ec2 describe-images failed in profile #{profile}:\n#{stderr}"
      end

      ami = stdout.lines.map(&:split).max_by(&:last)&.first
      if ami.nil?
        abort "No AMI matched '#{pattern}' in profile #{profile}.  Is '#{release}' a real ubuntu release name?"
      end

      ami
    end
  end
end
