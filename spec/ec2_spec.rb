require 'spec_helper'
require 'subspace/ec2'

describe Subspace::Ec2 do
  describe ".elastic_ip_headroom" do
    let(:quota_status) { instance_double Process::Status, success?: true }
    let(:quota_stderr) { "" }
    let(:addresses_status) { instance_double Process::Status, success?: true }

    before do
      allow(Open3).to receive(:capture3)
        .with("aws", "--profile", "subspace-test", "--region", "us-west-2", "service-quotas", "get-service-quota",
          "--service-code", "ec2", "--quota-code", "L-0263D0A3",
          "--query", "Quota.Value", "--output", "text")
        .and_return ["5.0\n", quota_stderr, quota_status]
      allow(Open3).to receive(:capture3)
        .with("aws", "--profile", "subspace-test", "--region", "us-west-2", "ec2", "describe-addresses",
          "--query", "length(Addresses[?ServiceManaged==null])", "--output", "text")
        .and_return ["3\n", "", addresses_status]
    end

    context "when both calls succeed" do
      it "is the quota less the addresses in use" do
        result = described_class.elastic_ip_headroom(profile: "subspace-test", region: "us-west-2")
        expect(result).to eq 2
      end
    end

    context "when the quota lookup fails" do
      let(:quota_status) { instance_double Process::Status, success?: false }

      it "names the permission" do
        expect { described_class.elastic_ip_headroom(profile: "subspace-test", region: "us-west-2") }
          .to raise_error(SystemExit)
          .and output(/servicequotas:GetServiceQuota/).to_stderr
      end
    end

    context "when the quota has never been adjusted" do
      let(:quota_status) { instance_double Process::Status, success?: false }
      let(:quota_stderr) { "An error occurred (NoSuchResourceException) when calling the GetServiceQuota operation" }

      it "uses the default quota of 5" do
        result = described_class.elastic_ip_headroom(profile: "subspace-test", region: "us-west-2")
        expect(result).to eq 2
      end
    end

    context "when describe-addresses fails" do
      let(:addresses_status) { instance_double Process::Status, success?: false }

      it "aborts naming the profile" do
        expect { described_class.elastic_ip_headroom(profile: "subspace-test", region: "us-west-2") }
          .to raise_error(SystemExit)
          .and output(/describe-addresses failed in profile subspace-test/).to_stderr
      end
    end
  end
end
