require 'open3'
module Subspace
  module Ami
    DEFAULT_RELEASE = "resolute"

    def self.latest(release:, profile:)
      pattern = "ubuntu/images/hvm-ssd-gp3/ubuntu-#{release}-*-amd64-server-*"
      stdout, stderr, status = Open3.capture3("aws", "--profile", profile, "ec2", "describe-images",
        "--owners", "099720109477",
        "--filters", "Name=name,Values=#{pattern}",
        "--query", "Images[*].[ImageId,CreationDate]", "--output", "text")
      abort "aws ec2 describe-images failed in profile #{profile}:\n#{stderr}" unless status.success?

      ami = stdout.lines.map(&:split).max_by(&:last)&.first
      if ami.nil?
        abort "No AMI matched '#{pattern}' in profile #{profile}.  Is '#{release}' a real ubuntu release name?"
      end

      ami
    end
  end
end
