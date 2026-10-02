require 'spec_helper'
require 'subspace/commands/db_copy'

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
end
