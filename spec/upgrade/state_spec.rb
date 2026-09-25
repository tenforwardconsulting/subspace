require 'spec_helper'
require 'subspace/upgrade'
require 'tmpdir'

describe Subspace::Upgrade::State do
  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir dir do
        FileUtils.mkdir_p "config/subspace/terraform/production"
        example.run
      end
    end
  end

  it "reports nothing in progress before it is created" do
    expect(described_class.exist?("production")).to eq false
  end

  it "round trips through yaml" do
    state = described_class.create "production", "template" => "workhorse", "phase" => "initialized"
    state["to_slot"] = "2"
    state.save

    reread = described_class.read "production"
    expect(reread["template"]).to eq "workhorse"
    expect(reread["to_slot"]).to eq "2"
    expect(reread.phase).to eq "initialized"
  end

  it "logs every phase it advances to" do
    state = described_class.create "production", "phase" => "initialized"
    state.advance! "prepared"
    state.advance! "cutover"

    log = described_class.read("production").data["log"]
    expect(log.map { |entry| entry["phase"] }).to eq %w[prepared cutover]
    expect(log.first["at"]).to match(/\A\d{4}-\d\d-\d\dT/)
  end

  it "passes require_phase! for the expected phase" do
    state = described_class.create "production", "phase" => "prepared"
    expect { state.require_phase! "prepared" }.not_to raise_error
  end

  it "aborts on require_phase! for any other phase" do
    state = described_class.create "production", "phase" => "initialized"
    expect { state.require_phase! "cutover" }.to raise_error SystemExit
  end

  it "deletes itself" do
    state = described_class.create "production", "phase" => "prepared"
    state.save
    state.destroy
    expect(described_class.exist?("production")).to eq false
  end
end
