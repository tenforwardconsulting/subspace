require 'spec_helper'
require 'subspace/upgrade'

describe Subspace::Upgrade::Terraform do
  subject { described_class.new "production" }

  let(:dir) { "config/subspace/terraform/production" }

  it "runs terraform with each argument passed through as-is" do
    allow(Open3).to receive(:capture3).and_return ["{}", "", instance_double(Process::Status, success?: true)]

    expect(subject.capture("output", "-json", "instances")).to eq "{}"
    expect(Open3).to have_received(:capture3).with("terraform", "output", "-json", "instances", chdir: dir)
  end

  it "aborts with terraform's error output when it fails" do
    allow(Open3).to receive(:capture3)
      .and_return ["", "Error: No outputs found", instance_double(Process::Status, success?: false)]

    expect { subject.output("instances") }
      .to raise_error(SystemExit)
      .and output(/terraform output -json instances failed:\nError: No outputs found/).to_stderr
  end
end
