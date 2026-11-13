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

  describe "#resources" do
    it "flattens the resources out of every nested module" do
      show_json = {
        "values" => {
          "root_module" => {
            "resources" => [{ "type" => "aws_root_resource" }],
            "child_modules" => [
              {
                "resources" => [
                  { "type" => "aws_child_resource_1" },
                  { "type" => "aws_child_resource_2" }
                ],
                "child_modules" => []
              }
            ]
          }
        }
      }
      allow(subject).to receive(:capture).with("show", "-json").and_return show_json.to_json

      types = subject.resources.map { |resource| resource["type"] }
      expect(types).to eq ["aws_root_resource", "aws_child_resource_1", "aws_child_resource_2"]
    end
  end

  describe "#key_pair_public_key" do
    it "reads the key pair public key" do
      show_json = {
        "values" => {
          "root_module" => {
            "resources" => [
              { "type" => "aws_key_pair", "values" => { "public_key" => "ssh-rsa AAAA..." } }
            ],
            "child_modules" => []
          }
        }
      }
      allow(subject).to receive(:capture).with("show", "-json").and_return show_json.to_json

      expect(subject.key_pair_public_key).to eq "ssh-rsa AAAA..."
    end
  end
end
