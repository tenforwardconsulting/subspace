require 'spec_helper'

describe Subspace::Configuration do
  before do
    Subspace.configure do |config|
      config.project_name = "configtest"

      config.host :dev, {
        ssh_host: "1.2.3.4",
        ssh_user: "deploy",
        sudo: true,
        hostname: "dev.example.com",
        group: :dev
      }
    end
  end
end
