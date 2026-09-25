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

  it "drops resources the plan leaves alone" do
    plan = {
      "resource_changes" => [
        { "address" => "aws_eip.single", "change" => { "actions" => ["no-op"] } },
        { "address" => "aws_instance.single[\"2\"]", "change" => { "actions" => ["create"] } }
      ]
    }
    allow(subject).to receive(:run).and_return true
    allow(subject).to receive(:capture).with("show", "-json", described_class::PLAN_FILE).and_return plan.to_json

    expect(subject.plan_changes.map { |change| change["address"] }).to eq ["aws_instance.single[\"2\"]"]
  end
end
