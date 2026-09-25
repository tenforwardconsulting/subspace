require 'spec_helper'
require 'commander'
require 'subspace/commands/base'
require 'subspace/commands/inventory'
require 'tmpdir'

describe Subspace::Commands::Inventory do
  let(:inventory) { Subspace::Inventory.read "spec/data/inventory_prod.yml" }

  it "writes a capistrano stage with an explicit rails_env" do
    Dir.mktmpdir do |dir|
      path = File.join dir, "deploy", "production_upgrade.rb"
      described_class.write_capistrano_stage inventory,
        group: "prod_web",
        rails_env: "production",
        path: path

      contents = File.read path
      expect(contents).to include "set :rails_env, 'production'"
      expect(contents).to include "user: 'deploy'"
    end
  end
end
