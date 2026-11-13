require 'open3'
module Subspace
  module AwsCli
    def self.run(*args, profile:, region:)
      stdout, stderr, status = Open3.capture3("aws", "--profile", profile, "--region", region, *args)
      abort yield(stderr) unless status.success?

      stdout
    end
  end
end
