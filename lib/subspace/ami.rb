module Subspace
  module Ami
    DEFAULT_RELEASE = "resolute"

    # Newest Canonical AMI for an ubuntu release name, e.g. "noble" or "resolute"
    def self.latest(release:, profile:)
      pattern = "ubuntu/images/hvm-ssd-gp3/ubuntu-#{release}-*-amd64-server-*"
      ami = `aws --profile #{profile} ec2 describe-images \
      --owners 099720109477 \
      --filters 'Name=name,Values=#{pattern}' \
      --query 'Images[*].[ImageId,CreationDate]' --output text \
      | sort -k2 -r \
      | head -n1 | cut -f1`.chomp

      if ami.empty?
        abort "No AMI matched '#{pattern}' in profile #{profile}.  Is '#{release}' a real ubuntu release name?"
      end

      ami
    end
  end
end
