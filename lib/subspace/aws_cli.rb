require 'open3'
module Subspace
  module AwsCli
    def self.run(*args, profile:, region:)
      stdout, stderr, status = Open3.capture3("aws", "--profile", profile, "--region", region, *args)
      return stdout if status.success?

      message = yield stderr
      abort message if message
    end
  end
end
