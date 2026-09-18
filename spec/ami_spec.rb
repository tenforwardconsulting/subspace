require 'spec_helper'
require 'subspace/ami'

describe Subspace::Ami do
  subject { described_class.latest release: "noble", profile: "subspace-atlas" }

  before do
    allow(described_class).to receive(:`).and_return "ami-0abc123\n"
  end

  it "restricts the search to Canonical's account" do
    subject
    expect(described_class).to have_received(:`).with(/--owners 099720109477/)
  end

  it "pins the gp3 volume type" do
    subject
    expect(described_class).to have_received(:`).with(%r{ubuntu/images/hvm-ssd-gp3/ubuntu-noble-})
  end
end
