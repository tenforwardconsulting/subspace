require 'spec_helper'
require 'commander'
require 'subspace/commands/base'
require 'subspace/commands/terraform'
require 'tmpdir'

describe Subspace::Commands::Terraform do
  describe ".terraform_cloud?" do
    around do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        example.run
      end
    end

    def terraform_cloud?(main_tf)
      File.write File.join(@dir, "main.tf"), main_tf
      described_class.terraform_cloud? @dir
    end

    it "detects a cloud block", :aggregate_failures do
      expect(terraform_cloud?(%(terraform {\n  cloud {\n    organization = "x"\n  }\n}\n))).to eq true
      expect(terraform_cloud?(%(terraform {\n  cloud{\n  }\n}\n))).to eq true
      expect(terraform_cloud?(%(cloud {\n}\n))).to eq true
    end

    it "detects the remote backend" do
      expect(terraform_cloud?(%(terraform {\n  backend "remote" {\n  }\n}\n))).to eq true
    end

    it "ignores commented-out and other backends", :aggregate_failures do
      expect(terraform_cloud?(%(terraform {\n  # cloud {\n  # }\n}\n))).to eq false
      expect(terraform_cloud?(%(terraform {\n  backend "s3" {\n  }\n}\n))).to eq false
    end
  end
end
