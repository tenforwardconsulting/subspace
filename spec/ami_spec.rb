require 'spec_helper'
require 'subspace/ami'

describe Subspace::Ami do
  subject { described_class.latest release: "noble", profile: "subspace-atlas" }

  let(:stdout) { "ami-0old\t2025-01-01T00:00:00.000Z\nami-0new\t2025-06-01T00:00:00.000Z\n" }
  let(:status) { instance_double Process::Status, success?: true }

  before do
    allow(Open3).to receive(:capture3).and_return [stdout, "", status]
  end

  it "restricts the search to Canonical's account" do
    subject
    expect(Open3).to have_received(:capture3) do |*args|
      expect(args.each_cons(2)).to include ["--owners", "099720109477"]
    end
  end

  it "pins the gp3 volume type" do
    subject
    expect(Open3).to have_received(:capture3) do |*args|
      expect(args).to include a_string_matching(%r{ubuntu/images/hvm-ssd-gp3/ubuntu-noble-})
    end
  end

  it "picks the newest image" do
    expect(subject).to eq "ami-0new"
  end

  context "when the aws cli fails" do
    let(:status) { instance_double Process::Status, success?: false }

    it "aborts rather than reporting an unknown release" do
      expect { subject }.to raise_error(SystemExit)
        .and output(/describe-images failed/).to_stderr
    end
  end
end
