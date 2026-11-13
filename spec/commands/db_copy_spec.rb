require 'spec_helper'
require 'subspace/commands/db_copy'
require 'tmpdir'

describe Subspace::Commands::DbCopy do
  let(:options) { Commander::Command::Options.new }
  let(:inventory) { double find_hosts!: true }
  let(:terraform) { double }
  let(:instances) { { "2" => { "hostname" => "production-app2", "private_ip" => "10.0.1.2" } } }

  before do
    allow_any_instance_of(described_class).to receive(:say)
    allow_any_instance_of(described_class).to receive(:inventory).and_return inventory
    allow_any_instance_of(described_class).to receive(:env).and_return "production"
    allow_any_instance_of(described_class).to receive(:terraform).and_return terraform
    allow_any_instance_of(described_class).to receive(:system).and_return true
    allow(terraform).to receive(:output).with("allow_instance_ssh").and_return true
    allow(terraform).to receive(:output).with("instances").and_return instances
  end

  it "passes the extra vars to ansible as JSON so values with spaces stay whole" do
    args = nil
    allow_any_instance_of(described_class).to receive(:ansible_playbook) { |_, *a| args = a }

    described_class.new %w[production-app1 production-app2], options

    expect(args[0]).to match(%r{ansible/playbooks/db_copy\.yml\z})
    expect(args[1]).to eq "-e"
    expect(JSON.parse(args[2])).to eq(
      "db_copy_source" => "production-app1",
      "db_copy_destination" => "production-app2",
      "db_copy_force" => false,
      "db_copy_overwrite" => false,
      "db_copy_destination_ip" => "10.0.1.2",
      "ansible_ssh_extra_args" => "-o ForwardAgent=yes",
      "ansible_control_path" => "/tmp/subspace-dbcopy-%%h-%%p-%%r"
    )
  end

  context "with --force and overwrite" do
    before { options.force = true }

    it "passes both through", :aggregate_failures do
      args = nil
      allow_any_instance_of(described_class).to receive(:ansible_playbook) { |_, *a| args = a }

      described_class.new %w[production-app1 production-app2], options, overwrite: true

      expect(JSON.parse(args.last)).to include("db_copy_force" => true, "db_copy_overwrite" => true)
    end
  end

  context "when only checking" do
    it "runs just the check tag" do
      args = nil
      allow_any_instance_of(described_class).to receive(:ansible_playbook) { |_, *a| args = a }

      described_class.new %w[production-app1 production-app2], options, check_only: true

      expect(args[1..2]).to eq ["--tags", "db_copy_check"]
    end
  end

  it "forwards the key through the agent with mitogen disabled, then puts both back", :aggregate_failures do
    was = ENV["DISABLE_MITOGEN"]
    mitogen = nil
    allow_any_instance_of(described_class).to receive(:ansible_playbook) { mitogen = ENV["DISABLE_MITOGEN"] }

    calls = []
    allow_any_instance_of(described_class).to receive(:system) { |_, *a| calls << a }

    described_class.new %w[production-app1 production-app2], options

    expect(calls).to eq [%w[ssh-add -t 3600 config/subspace/subspace.pem], %w[ssh-add -d config/subspace/subspace.pem]]
    expect(mitogen).to eq "1"
    expect(ENV["DISABLE_MITOGEN"]).to eq was
  end

  context "when the playbook fails" do
    before { allow_any_instance_of(described_class).to receive(:ansible_playbook).and_return false }

    it "still takes the key back out of the agent" do
      expect_any_instance_of(described_class).to receive(:system).with("ssh-add", "-d", "config/subspace/subspace.pem")

      expect { described_class.new %w[production-app1 production-app2], options }.to raise_error SystemExit, /db_copy from production-app1 to production-app2 failed/
    end
  end

  context "when the key cannot be added to the agent" do
    before { allow_any_instance_of(described_class).to receive(:system).with("ssh-add", "-t", any_args).and_return false }

    it "aborts before running the playbook" do
      expect_any_instance_of(described_class).not_to receive(:ansible_playbook)

      expect { described_class.new %w[production-app1 production-app2], options }.to raise_error SystemExit, /Is ssh-agent running\?/
    end
  end

  context "when instance ssh is closed" do
    before { allow(terraform).to receive(:output).with("allow_instance_ssh").and_return false }

    it "refuses, pointing at the upgrade that opens it" do
      expect_any_instance_of(described_class).not_to receive(:ansible_playbook)

      expect { described_class.new %w[production-app1 production-app2], options }.to raise_error SystemExit, /subspace upgrade production --copy-db/
    end
  end

  context "when the destination is not in the terraform output" do
    let(:instances) { { "1" => { "hostname" => "production-app1", "private_ip" => "10.0.1.1" } } }

    it "aborts" do
      expect_any_instance_of(described_class).not_to receive(:ansible_playbook)

      expect { described_class.new %w[production-app1 production-app2], options }.to raise_error SystemExit, /production-app2 is not in production's terraform output/
    end
  end

  context "without a source or destination" do
    it "prints the usage and exits" do
      expect { described_class.new %w[production-app1], options }.to raise_error SystemExit
    end
  end

  describe "the environment" do
    let(:inventory) { double find_hosts!: true, hosts: { "production-app2" => double(group_list: groups) } }

    around do |example|
      Dir.mktmpdir do |dir|
        Dir.chdir dir do
          FileUtils.mkdir_p "config/subspace/terraform/production"
          example.run
        end
      end
    end

    before do
      allow_any_instance_of(described_class).to receive(:env).and_call_original
      allow_any_instance_of(described_class).to receive(:terraform).and_call_original
      allow_any_instance_of(described_class).to receive(:ansible_playbook).and_return true
      allow(Subspace::Upgrade::Terraform).to receive(:new).and_return terraform
    end

    context "when one of the destination's groups has a terraform directory" do
      let(:groups) { %w[production_web production upgrade] }

      it "is that group" do
        described_class.new %w[production-app1 production-app2], options

        expect(Subspace::Upgrade::Terraform).to have_received(:new).with("production")
      end
    end

    context "when none does" do
      let(:groups) { %w[production_web upgrade] }

      it "aborts naming the groups" do
        expect { described_class.new %w[production-app1 production-app2], options }
          .to raise_error SystemExit, /production-app2 belongs to \(groups: production_web, upgrade\)/
      end
    end
  end
end
