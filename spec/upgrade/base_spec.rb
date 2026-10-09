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

  describe "#apply!" do
    let(:terraform) { double discard_plan: nil, apply_plan: nil }

    let(:expected_changes) do
      [{ "address" => "module.workhorse.aws_security_group.single", "change" => { "actions" => ["update"] } }]
    end

    let(:close_changes) { expected_changes }

    before do
      allow(subject).to receive(:terraform).and_return terraform
      allow(subject).to receive(:ask).and_return "y"
      allow(terraform).to receive(:plan_changes).and_return changes
    end

    context "when the plan toggles the rule on the server group in place" do
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

    context "when the plan replaces the server group the step only asked to update" do
      let(:changes) do
        [{ "address" => "module.workhorse.aws_security_group.single", "change" => { "actions" => %w[delete create] } }]
      end

      it "refuses and discards the plan", :aggregate_failures do
        expect { subject.send :open_instance_ssh! }.to raise_error SystemExit
        expect(terraform).to have_received :discard_plan
        expect(terraform).not_to have_received :apply_plan
      end
    end

    context "when the prompt hits end of input" do
      let(:changes) { expected_changes }

      before { allow(subject).to receive(:ask).and_raise EOFError }

      it "puts main.tf back", :aggregate_failures do
        expect { subject.send :open_instance_ssh! }.to raise_error EOFError
        expect(terraform).not_to have_received :apply_plan
        expect(File.read(subject.config.path)).to eq main_tf
      end
    end

    context "when the plan replaces a resource the step permits every action on" do
      let(:changes) do
        [{ "address" => "module.workhorse.aws_eip_association.eip_assoc", "change" => { "actions" => %w[delete create] } }]
      end

      before do
        Subspace::Upgrade::State.create("production", "phase" => "copied").save
      end

      it "applies the saved plan" do
        subject.send :flip_active_instance!, "2"
        expect(terraform).to have_received :apply_plan
      end
    end

    context "when the step records the phase terraform is applying" do
      let(:changes) do
        [{ "address" => "module.workhorse.aws_eip_association.eip_assoc", "change" => { "actions" => ["update"] } }]
      end

      before do
        Subspace::Upgrade::State.create("production", "phase" => "copied").save
        allow(terraform).to receive(:apply_plan) { abort "terraform apply failed" }
      end

      it "records it before terraform applies anything" do
        expect { subject.send :flip_active_instance!, "2" }.to raise_error SystemExit
        expect(Subspace::Upgrade::State.read("production").phase).to eq "cutting_over"
      end

      context "when the plan is declined" do
        before { allow(subject).to receive(:ask).and_return "n" }

        it "does not record it" do
          expect { subject.send :flip_active_instance!, "2" }.to raise_error SystemExit
          expect(Subspace::Upgrade::State.read("production").phase).to eq "copied"
        end
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

  describe "#check_module_version!" do
    let(:module_dir) { "config/subspace/terraform/production/modules/workhorse" }

    def write_manifest(template: "workhorse", ref: "v2.0.0")
      FileUtils.mkdir_p module_dir
      Subspace::Upgrade::ModuleManifest.write module_dir, template:, repo: "https://example.com/workhorse.git", ref:
    end

    context "when the vendored module is at the minimum ref" do
      before { write_manifest }

      it "returns without aborting" do
        expect { subject.send :check_module_version! }.not_to raise_error
      end
    end

    context "when the vendored module is older" do
      before { write_manifest ref: "v1.0.0" }

      it "aborts with the migration instructions" do
        expect { subject.send :check_module_version! }.to raise_error SystemExit, /v1\.0\.0 \(needs >= v2\.0\.0\).*To migrate production/m
      end
    end

    context "when the vendored module is pinned to a branch" do
      before { write_manifest ref: "main" }

      it "treats it as too old" do
        expect { subject.send :check_module_version! }.to raise_error SystemExit, /needs >= v2\.0\.0/
      end
    end

    context "when the vendored module is for another template" do
      before { write_manifest template: "oxenwagen" }

      it "aborts" do
        expect { subject.send :check_module_version! }.to raise_error SystemExit, /is a oxenwagen module, not workhorse/
      end
    end

    context "when the vendored module has no manifest" do
      it "aborts with the migration instructions" do
        expect { subject.send :check_module_version! }.to raise_error SystemExit, /no module\.yml.*To migrate production/m
      end
    end

    context "when main.tf references the module by git URL" do
      let(:module_block) do
        <<~HCL
          module workhorse {
            source = "github.com/tenforwardconsulting/terraform-subspace-workhorse?ref=#{ref}"
          }
        HCL
      end

      context "at the minimum ref" do
        let(:ref) { "v2.0.0" }

        it "reads the ref from the source" do
          expect { subject.send :check_module_version! }.not_to raise_error
        end
      end

      context "at an older ref" do
        let(:ref) { "v1.0.0" }

        it "aborts" do
          expect { subject.send :check_module_version! }.to raise_error SystemExit, /v1\.0\.0 \(needs >= v2\.0\.0\)/
        end
      end
    end
  end

  describe "#check_module_variables!" do
    let(:variables) { %w[instances active_instance allow_instance_ssh] }

    before do
      FileUtils.mkdir_p module_dir
      File.write File.join(module_dir, "variables.tf"), variables.map { |name| %(variable "#{name}" {}\n) }.join
    end

    context "with a vendored module that declares every variable" do
      let(:module_dir) { "config/subspace/terraform/production/modules/workhorse" }

      it "returns without aborting" do
        expect { subject.send :check_module_variables! }.not_to raise_error
      end

      context "but is missing one" do
        let(:variables) { %w[instances active_instance] }

        before do
          Subspace::Upgrade::ModuleManifest.write module_dir, template: "workhorse", repo: "https://example.com/workhorse.git", ref: "v2.0.0"
        end

        it "aborts naming it" do
          expect { subject.send :check_module_variables! }.to raise_error SystemExit, /does not declare allow_instance_ssh/
        end
      end
    end

    context "with a module terraform init downloaded" do
      let(:module_dir) { "config/subspace/terraform/production/.terraform/modules/workhorse" }

      it "reads that one" do
        expect { subject.send :check_module_variables! }.not_to raise_error
      end
    end

    context "with no module on disk" do
      let(:module_dir) { "tmp/elsewhere" }

      it "aborts asking for terraform init" do
        expect { subject.send :check_module_variables! }.to raise_error SystemExit, /Run `terraform init`/
      end
    end
  end

  describe "#check_instance_ssh!" do
    context "with no upgrade in progress" do
      it "aborts while the servers can ssh to each other" do
        expect { subject.send :check_instance_ssh! }.to raise_error SystemExit, /only be open from --launch until --finalize/
      end
    end

    %w[launching launched prepared copied cutting_over cutover].each do |phase|
      context "when #{phase}" do
        before { Subspace::Upgrade::State.create("production", "phase" => phase).save }

        it "lets the servers ssh to each other" do
          expect { subject.send :check_instance_ssh! }.not_to raise_error
        end
      end
    end

    %w[initialized finalizing finalized aborting].each do |phase|
      context "when #{phase}" do
        before { Subspace::Upgrade::State.create("production", "phase" => phase).save }

        it "aborts while the servers can ssh to each other" do
          expect { subject.send :check_instance_ssh! }.to raise_error SystemExit
        end
      end
    end
  end

  describe "#check_subspace_key!" do
    let(:terraform) { instance_double Subspace::Upgrade::Terraform, key_pair_public_key: authorized }
    let(:pem) { "config/subspace/subspace.pem" }

    before do
      system "ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "pem", "-f", pem, exception: true
      allow(subject).to receive(:terraform).and_return terraform
    end

    context "when state holds the pem's public key" do
      let(:authorized) { File.read("#{pem}.pub").sub("pem", "another comment") }

      it "returns without aborting" do
        expect { subject.send :check_subspace_key! }.not_to raise_error
      end
    end

    context "when state holds a different key" do
      let(:authorized) do
        system "ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", "other", exception: true
        File.read "other.pub"
      end

      it "aborts with how to fix it" do
        expect { subject.send :check_subspace_key! }.to raise_error SystemExit, /not the public half.*ssh-keygen -y/m
      end
    end

    context "when state has no key pair" do
      let(:authorized) { nil }

      it "aborts" do
        expect { subject.send :check_subspace_key! }.to raise_error SystemExit, /No aws_key_pair/
      end
    end
  end

  describe "#check_state_fingerprint!" do
    let(:terraform) { instance_double Subspace::Upgrade::Terraform, state_list: addresses }

    before { allow(subject).to receive(:terraform).and_return terraform }

    context "with keyed instance slots" do
      let(:addresses) { [%(module.workhorse.aws_instance.single["1"]), "module.workhorse.aws_eip.single"] }

      it "returns without aborting" do
        expect { subject.send :check_state_fingerprint! }.not_to raise_error
      end
    end

    context "with an unkeyed instance" do
      let(:addresses) { ["module.workhorse.aws_instance.single", "module.workhorse.aws_eip.single"] }

      it "aborts with the migration instructions" do
        expect { subject.send :check_state_fingerprint! }.to raise_error SystemExit, /unkeyed aws_instance\.single.*To migrate production/m
      end
    end

    context "with a resource another template uses" do
      let(:addresses) { [%(module.workhorse.aws_instance.single["1"]), "module.workhorse.aws_lb.web"] }

      it "aborts naming it" do
        expect { subject.send :check_state_fingerprint! }.to raise_error SystemExit, /present but forbidden: aws_lb/
      end
    end

    context "without an instance" do
      let(:addresses) { ["module.workhorse.aws_eip.single"] }

      it "aborts naming it" do
        expect { subject.send :check_state_fingerprint! }.to raise_error SystemExit, /expected but missing:  aws_instance\.single/
      end
    end

    context "with no state" do
      let(:addresses) { [] }

      it "aborts" do
        expect { subject.send :check_state_fingerprint! }.to raise_error SystemExit, /Has it been applied\?/
      end
    end
  end

  describe "#check_clean_plan!" do
    let(:terraform) { instance_double Subspace::Upgrade::Terraform, plan_exit_status: status }

    before { allow(subject).to receive(:terraform).and_return terraform }

    context "when the plan is empty" do
      let(:status) { 0 }

      it "returns without aborting" do
        expect { subject.send :check_clean_plan! }.not_to raise_error
      end
    end

    context "when the plan has changes" do
      let(:status) { 2 }

      it "aborts" do
        expect { subject.send :check_clean_plan! }.to raise_error SystemExit, /is not empty/
      end
    end

    context "when terraform plan fails" do
      let(:status) { 1 }

      it "aborts with the exit status" do
        expect { subject.send :check_clean_plan! }.to raise_error SystemExit, /failed \(exit 1\)/
      end
    end
  end

  describe "#check_tailscale!" do
    let(:roles) { "      - common\n      - tailscale\n" }
    let(:app1_address) { "100.67.24.117" }

    before do
      File.write "config/subspace/production.yml", "---\n- hosts: production\n  roles:\n#{roles}"
      File.write "config/subspace/inventory.yml", <<~YML
        all:
          hosts:
            production-app1:
              ansible_host: #{app1_address}
            staging-app1:
              ansible_host: 203.0.113.7
          children:
            production:
              hosts:
                production-app1:
            staging:
              hosts:
                staging-app1:
      YML
    end

    it "returns when every server in the environment is on the tailnet" do
      expect { subject.send :check_tailscale! }.not_to raise_error
    end

    context "when the playbook does not include the tailscale role" do
      let(:roles) { "      - common\n" }

      it "aborts" do
        expect { subject.send :check_tailscale! }.to raise_error SystemExit, /does not include the tailscale role/
      end
    end

    context "when a server is addressed by its public IP" do
      let(:app1_address) { "203.0.113.1" }

      it "aborts naming it" do
        expect { subject.send :check_tailscale! }.to raise_error SystemExit, /production-app1 is not addressed by tailscale IP/
      end
    end
  end

  describe "#check_remote_storage!" do
    before do
      FileUtils.mkdir_p "config/environments"
      File.write "config/environments/production.rb", "  config.active_storage.service = :#{service}\n"
      File.write "config/storage.yml", <<~YAML
        local:
          service: Disk
          root: <%= Rails.root.join("storage") %>

        amazon:
          service: S3
          bucket: <%= ENV["BUCKET"] %>
      YAML
    end

    context "when the environment uses a Disk service" do
      let(:service) { "local" }

      it "aborts" do
        expect { subject.send :check_remote_storage! }.to raise_error SystemExit, /local disk \(:local\)/
      end
    end

    context "when the environment uses S3" do
      let(:service) { "amazon" }

      it "returns without aborting" do
        expect { subject.send :check_remote_storage! }.not_to raise_error
      end
    end

    context "without active storage" do
      let(:service) { "local" }

      before { File.delete "config/storage.yml" }

      it "returns without aborting" do
        expect { subject.send :check_remote_storage! }.not_to raise_error
      end
    end
  end

  describe "#assert_clean_git_tree!" do
    before do
      system "git init -q && git add . && git -c user.name=t -c user.email=t@t commit -qm init", exception: true
    end

    context "when only the upgrade state file has changed" do
      before { File.write "config/subspace/terraform/production/upgrade.yml", "phase: initialized\n" }

      it "returns without aborting" do
        expect { subject.send :assert_clean_git_tree! }.not_to raise_error
      end
    end

    context "when main.tf has changed" do
      before { File.write "config/subspace/terraform/production/main.tf", "#{main_tf}\n# edited\n" }

      it "aborts" do
        expect { subject.send :assert_clean_git_tree! }.to raise_error SystemExit, /working tree is dirty/
      end
    end
  end

  describe "#update_gitignore!" do
    let(:path) { "config/subspace/terraform/.gitignore" }

    context "when the project predates the upgrade entries" do
      before { File.write path, "credentials.auto.tfvars\n.subspace-tf-modules\n" }

      it "appends only the missing entries" do
        subject.send :update_gitignore!

        expect(File.read(path)).to eq "credentials.auto.tfvars\n.subspace-tf-modules\nsubspace-upgrade.tfplan\n*.bak\n"
      end
    end

    context "when it already has every entry" do
      before { File.write path, "credentials.auto.tfvars\n.subspace-tf-modules\nsubspace-upgrade.tfplan\n*.bak\n# local\n" }

      it "leaves it alone" do
        expect { subject.send :update_gitignore! }.not_to(change { File.read path })
      end
    end
  end

  describe "#revendor" do
    let(:module_block) do
      <<~HCL
        module workhorse {
          source = "github.com/tenforwardconsulting/terraform-subspace-workhorse?ref=v1.0.0"
          instance_hostname = "production-app1"
        }
      HCL
    end

    before do
      allow(subject).to receive(:system) { |*args| FileUtils.mkdir_p args.last }
    end

    it "points main.tf at the vendored module" do
      subject.revendor

      expect(File.read("config/subspace/terraform/production/main.tf")).to include 'source = "./modules/workhorse"'
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
      subject.send :playbook, "upgrade_verify", "production-app2", upgrade_host: "production-app2"

      expect(subject).to have_received(:ansible_playbook).with(
        %r{ansible/playbooks/upgrade_verify\.yml\z},
        "--limit", "production-app2",
        "-e", '{"upgrade_host":"production-app2"}'
      )
    end

    context "with several hosts" do
      it "joins them into one limit" do
        subject.send :playbook, "upgrade_verify", %w[production-app1 production-app2], a: "b"

        expect(subject).to have_received(:ansible_playbook).with(
          anything,
          "--limit", "production-app1,production-app2",
          "-e", '{"a":"b"}'
        )
      end
    end
  end
end
