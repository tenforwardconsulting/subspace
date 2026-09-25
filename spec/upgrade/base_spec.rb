require 'spec_helper'
require 'subspace/upgrade'
require 'tmpdir'

describe Subspace::Upgrade::Workhorse do
  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir dir do
        FileUtils.mkdir_p "config/subspace/terraform/production"
        example.run
      end
    end
  end

  let(:module_block) do
    <<~HCL
      module workhorse {
        source = "./modules/workhorse"
        project_name = "test_project"
        instance_user = "ubuntu"

        instances = {
          "1" = {
            hostname      = "production-app1"
            ami           = "ami-0abc"
            instance_type = "t3.medium"
            volume_size   = 20
          }
          "2" = {
            hostname      = "production-app2"
            ami           = "ami-0def"
            instance_type = "t3.medium"
            volume_size   = 20
          }
        }
        active_instance = "1"
        allow_instance_ssh = true
      }
    HCL
  end

  let(:main_tf) do
    <<~HCL
      #{module_block}
      output "workhorse" {
        value = module.workhorse
      }
    HCL
  end

  let(:options) { double }

  subject { described_class.new "production", options }

  before do
    File.write "config/subspace/terraform/production/main.tf", main_tf
    allow(subject).to receive(:say)
  end

  describe "#slot_addresses" do
    it "returns one keyed, module-qualified entry per slot" do
      expect(subject.slot_addresses("update")).to eq(
        %(module.workhorse.aws_instance.single["1"]) => ["update"],
        %(module.workhorse.aws_instance.single["2"]) => ["update"]
      )
    end
  end

  describe "#apply!" do
    let(:terraform) { double discard_plan: nil, apply_plan: nil }

    let(:expected_changes) do
      [
        { "address" => %(module.workhorse.aws_instance.single["1"]), "change" => { "actions" => ["update"] } },
        { "address" => %(module.workhorse.aws_instance.single["2"]), "change" => { "actions" => ["update"] } },
        { "address" => "module.workhorse.aws_security_group.instance_ssh[0]", "change" => { "actions" => ["create"] } }
      ]
    end

    let(:close_changes) do
      [
        { "address" => %(module.workhorse.aws_instance.single["1"]), "change" => { "actions" => ["update"] } },
        { "address" => %(module.workhorse.aws_instance.single["2"]), "change" => { "actions" => ["update"] } },
        { "address" => "module.workhorse.aws_security_group.instance_ssh[0]", "change" => { "actions" => ["delete"] } }
      ]
    end

    before do
      allow(subject).to receive(:terraform).and_return terraform
      allow(subject).to receive(:ask).and_return "y"
      allow(terraform).to receive(:plan_changes).and_return changes
    end

    context "when the plan holds the keyed update for_each emits on every slot" do
      let(:changes) { expected_changes }

      it "applies the saved plan", :aggregate_failures do
        expect { subject.send :open_instance_ssh! }.not_to raise_error
        expect(terraform).to have_received :apply_plan
        expect(terraform).not_to have_received :discard_plan
      end
    end

    context "when closing the window the copy opened" do
      let(:changes) { close_changes }

      it "applies the saved plan", :aggregate_failures do
        expect { subject.close_instance_ssh }.not_to raise_error
        expect(terraform).to have_received :apply_plan
        expect(terraform).not_to have_received :discard_plan
      end
    end

    context "when the plan also does something the step did not ask for" do
      let(:changes) do
        expected_changes + [
          { "address" => "module.workhorse.aws_eip.single", "change" => { "actions" => ["delete"] } }
        ]
      end

      it "refuses, discards the plan and puts main.tf back", :aggregate_failures do
        expect { subject.send :open_instance_ssh! }.to raise_error SystemExit
        expect(terraform).to have_received :discard_plan
        expect(terraform).not_to have_received :apply_plan
        expect(File.read(subject.config.path)).to eq main_tf
      end
    end

    context "when the operator declines the plan" do
      let(:changes) { close_changes }

      before { allow(subject).to receive(:ask).and_return "n" }

      it "discards the plan and puts main.tf back", :aggregate_failures do
        expect { subject.close_instance_ssh }.to raise_error SystemExit
        expect(terraform).to have_received :discard_plan
        expect(terraform).not_to have_received :apply_plan
        expect(File.read(subject.config.path)).to eq main_tf
        expect(subject.config.allow_instance_ssh).to eq true
      end
    end

    context "when terraform plan fails" do
      let(:changes) { nil }

      before { allow(terraform).to receive(:plan_changes) { abort "terraform plan failed" } }

      it "puts main.tf back" do
        expect { subject.close_instance_ssh }.to raise_error SystemExit
        expect(File.read(subject.config.path)).to eq main_tf
      end
    end

    context "when an earlier step in the same run was applied" do
      let(:changes) { nil }

      before { allow(terraform).to receive(:plan_changes).and_return close_changes, expected_changes }

      it "puts main.tf back to what was last applied, not to what was first read", :aggregate_failures do
        subject.close_instance_ssh
        applied = File.read subject.config.path

        allow(subject).to receive(:ask).and_return "n"
        expect { subject.send :open_instance_ssh! }.to raise_error SystemExit
        expect(File.read(subject.config.path)).to eq applied
        expect(subject.config.allow_instance_ssh).to eq false
      end
    end
  end

  describe "#check_root_outputs!" do
    context "when the root file only re-exports the whole module" do
      it "aborts naming every output the upgrade reads" do
        expect { subject.send :check_root_outputs! }
          .to raise_error SystemExit, /inventory, instances, active_instance, allow_instance_ssh/
      end
    end

    context "when the root file re-exports each one" do
      let(:main_tf) do
        <<~HCL
          #{module_block}
          output "inventory" {
            value = module.workhorse.inventory
          }

          output "instances" {
            value = module.workhorse.instances
          }

          output "active_instance" {
            value = module.workhorse.active_instance
          }

          output "allow_instance_ssh" {
            value = module.workhorse.allow_instance_ssh
          }
        HCL
      end

      it "returns without aborting" do
        expect { subject.send :check_root_outputs! }.not_to raise_error
      end
    end
  end

  describe "the shipped workhorse template" do
    let(:template) do
      File.read File.expand_path("../../template/subspace/terraform/template/main-workhorse.tf.erb", __dir__)
    end

    it "re-exports every required root output", :aggregate_failures do
      described_class::REQUIRED_ROOT_OUTPUTS.each do |name|
        expect(template).to match(/^output\s+"#{name}"\s*\{/)
      end
    end
  end

  describe "#playbook" do
    before { allow(subject).to receive(:ansible_playbook) }

    it "limits the run to the host it asserts against" do
      subject.send :playbook, "upgrade_verify", "production-app2", "upgrade_host=production-app2"

      expect(subject).to have_received(:ansible_playbook).with(
        %r{ansible/playbooks/upgrade_verify\.yml\z},
        "--limit", "production-app2",
        "-e", "upgrade_host=production-app2"
      )
    end

    context "with several hosts" do
      it "joins them into one limit" do
        subject.send :playbook, "upgrade_verify", %w[production-app1 production-app2], "a=b"

        expect(subject).to have_received(:ansible_playbook).with(
          anything,
          "--limit", "production-app1,production-app2",
          "-e", "a=b"
        )
      end
    end
  end
end
