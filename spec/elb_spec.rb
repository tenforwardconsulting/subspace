require 'spec_helper'
require 'subspace/upgrade'

describe Subspace::Elb do
  describe ".target_health" do
    let(:status) { instance_double Process::Status, success?: true }

    before do
      allow(Open3).to receive(:capture3).and_return [stdout, "", status]
    end

    context "when the call succeeds" do
      let(:stdout) do
        {
          "TargetHealthDescriptions" => [
            {
              "Target" => { "Id" => "i-1" },
              "TargetHealth" => { "State" => "healthy" }
            },
            {
              "Target" => { "Id" => "i-2" },
              "TargetHealth" => { "State" => "unhealthy" }
            }
          ]
        }.to_json
      end

      it "maps each target id to its state" do
        result = described_class.target_health("arn:aws:elasticloadbalancing:...", profile: "subspace-test", region: "us-west-2")
        expect(result).to eq({ "i-1" => "healthy", "i-2" => "unhealthy" })
      end
    end

    context "when nothing is registered" do
      let(:stdout) do
        { "TargetHealthDescriptions" => [] }.to_json
      end

      it "is empty" do
        result = described_class.target_health("arn:aws:elasticloadbalancing:...", profile: "subspace-test", region: "us-west-2")
        expect(result).to eq({})
      end
    end

    context "when the aws call fails" do
      let(:status) { instance_double Process::Status, success?: false }
      let(:stdout) { "" }

      it "aborts naming the profile" do
        expect { described_class.target_health("arn:aws:...", profile: "subspace-test", region: "us-west-2") }
          .to raise_error(SystemExit)
          .and output(/describe-target-health failed in profile subspace-test/).to_stderr
      end
    end
  end
end
