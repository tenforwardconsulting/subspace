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

  let(:main_tf) do
    <<~HCL
      module workhorse {
        source = "./modules/workhorse"

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
        allow_instance_ssh = false
      }
    HCL
  end

  let(:options) { double }

  subject { described_class.new "production", options }

  before do
    File.write "config/subspace/terraform/production/main.tf", main_tf
    Subspace::Upgrade::State.create("production",
      "template" => "workhorse",
      "phase" => "prepared",
      "from_hostname" => "production-app1",
      "to_hostname" => "production-app2").save

    allow(subject).to receive(:say)
    allow(subject).to receive(:ask).and_return "y"
    allow(subject).to receive(:check!)
    allow(subject).to receive(:verify_deployed!)
    allow(subject).to receive(:maintenance_mode!)
    allow(subject).to receive(:verify_maintenance_page!)
    allow(subject).to receive(:stop_application!)
    allow(subject).to receive(:open_instance_ssh!)
    allow(subject).to receive(:close_instance_ssh)
    allow(subject).to receive(:check_db_copy!)
    allow(subject).to receive(:db_copy!)
    allow(subject).to receive(:next_step_for)
  end

  def reread_phase
    Subspace::Upgrade::State.read("production").phase
  end

  describe "#copy_letsencrypt!" do
    let(:archive) { File.expand_path "tmp/subspace/production-letsencrypt.tar.gz" }

    before do
      allow(subject).to receive(:playbook) do
        FileUtils.touch archive
        true
      end
    end

    it "limits each run to the one host it acts on" do
      subject.send :copy_letsencrypt!

      expect(subject).to have_received(:playbook).with(
        "upgrade_fetch_letsencrypt",
        "production-app1",
        upgrade_host: "production-app1",
        letsencrypt_archive: archive
      )
      expect(subject).to have_received(:playbook).with(
        "upgrade_push_letsencrypt",
        "production-app2",
        upgrade_host: "production-app2",
        letsencrypt_archive: archive
      )
    end

    it "does not push when the fetch fails" do
      allow(subject).to receive(:playbook).and_return(false)

      expect { subject.send :copy_letsencrypt! }.to raise_error(SystemExit)
      expect(subject).not_to have_received(:playbook).with("upgrade_push_letsencrypt", any_args)
    end

    it "does not leave the private keys on this machine" do
      subject.send :copy_letsencrypt!

      expect(File).not_to exist archive
    end
  end

  describe "#launch" do
    let(:options) { double ami: "ami-0new", ubuntu_release: "noble" }

    let(:main_tf) do
      <<~HCL
        module workhorse {
          source = "./modules/workhorse"

          instances = {
            "1" = {
              hostname      = "production-app1"
              ami           = "ami-0abc"
              instance_type = "t3.medium"
              volume_size   = 20
            }
          }
          active_instance = "1"
          allow_instance_ssh = false
        }
      HCL
    end

    before do
      Subspace::Upgrade::State.create("production", "template" => "workhorse", "phase" => "initialized").save
      allow(subject).to receive(:assert_clean_git_tree!)
      allow(subject).to receive(:confirm_database_backup!)
      allow(subject).to receive(:apply!)
      allow(subject).to receive(:update_inventory!)
      allow(subject).to receive(:add_to_group!)
    end

    it "records launching before terraform creates the new slot", :aggregate_failures do
      subject.launch

      expect(subject).to have_received(:apply!)
        .with({ %(module.workhorse.aws_instance.single["2"]) => ["create"] }, starting: "launching")
      expect(reread_phase).to eq "launched"
    end

    context "when a previous launch did not finish" do
      let(:main_tf) do
        <<~HCL
          module workhorse {
            source = "./modules/workhorse"

            instances = {
              "1" = {
                hostname      = "production-app1"
                ami           = "ami-0abc"
                instance_type = "t3.medium"
                volume_size   = 20
              }
              "2" = {
                hostname      = "production-app2"
                ami           = "ami-0new"
                instance_type = "t3.medium"
                volume_size   = 20
              }
            }
            active_instance = "1"
            allow_instance_ssh = false
          }
        HCL
      end

      before do
        Subspace::Upgrade::State.create("production",
          "template" => "workhorse",
          "phase" => "launching",
          "from_hostname" => "production-app1",
          "to_slot" => "2",
          "to_hostname" => "production-app2").save
      end

      it "finishes creating the slot it already picked", :aggregate_failures do
        subject.launch

        expect(subject).to have_received(:check!).with(clean_plan: false)
        expect(subject).not_to have_received :confirm_database_backup!
        expect(subject).to have_received(:apply!)
          .with({ %(module.workhorse.aws_instance.single["2"]) => ["create"] }, starting: "launching")
        expect(subject).to have_received(:add_to_group!).with("production-app2", "upgrade")
        expect(reread_phase).to eq "launched"
      end
    end
  end

  describe "#provision" do
    before do
      Subspace::Upgrade::State.read("production").tap { |state| state["phase"] = "launched" }.save
      allow(Subspace::Commands::Bootstrap).to receive(:new)
      allow(subject).to receive(:copy_letsencrypt!)
      allow(subject).to receive(:provision!)
      allow(subject).to receive(:write_capistrano_stage!)
    end

    it "advances to prepared" do
      subject.provision

      expect(reread_phase).to eq "prepared"
    end

    context "when provisioning fails" do
      before { allow(subject).to receive(:provision!) { abort "Provisioning failed." } }

      it "stays launched, so it can be run again", :aggregate_failures do
        expect { subject.provision }.to raise_error SystemExit
        expect(reread_phase).to eq "launched"
      end
    end

    context "when already prepared" do
      before { Subspace::Upgrade::State.read("production").tap { |state| state["phase"] = "prepared" }.save }

      it "provisions again" do
        subject.provision

        expect(subject).to have_received(:provision!).with("production-app2")
      end
    end
  end

  describe "#write_capistrano_stage!" do
    let(:base_stage) do
      <<~RUBY
        # Tailscale IP:
        server '100.80.6.11', user: 'deploy', roles: %w{web app db}, ssh_options: { forward_agent: true }
        # server '3.137.61.218', user: 'deploy', roles: %w{web app db}
        set :rails_env, "production"
        set :branch, "production"
      RUBY
    end

    before do
      File.write "config/subspace/inventory.yml", <<~YML
        all:
          hosts:
            production-app2:
              ansible_host: 203.0.113.2
          children:
            upgrade:
              hosts:
                production-app2:
      YML
      FileUtils.mkdir_p "config/deploy"
      File.write "config/deploy/production.rb", base_stage
    end

    it "copies the base stage, pointing its server at the new host" do
      subject.send :write_capistrano_stage!

      expect(File.read("config/deploy/production_upgrade.rb")).to eq <<~RUBY
        # Generated by Subspace from config/deploy/production.rb
        # Tailscale IP:
        server '203.0.113.2', user: 'deploy', roles: %w{web app db}, ssh_options: { forward_agent: true }
        # server '3.137.61.218', user: 'deploy', roles: %w{web app db}
        set :rails_env, "production"
        set :branch, "production"
      RUBY
    end

    context "when the base stage has no server line" do
      let(:base_stage) { %(set :branch, "production"\n) }

      it "refuses, so the stage cannot deploy to the old server", :aggregate_failures do
        expect { subject.send :write_capistrano_stage! }.to raise_error SystemExit
        expect(File).not_to exist "config/deploy/production_upgrade.rb"
      end
    end
  end

  describe "#cutover" do
    before do
      Subspace::Upgrade::State.read("production").tap { |state| state["phase"] = "copied" }.save
      allow(subject).to receive(:to_public_ip).and_return "203.0.113.2"
      allow(subject).to receive(:flip_active_instance!)
      allow(subject).to receive(:serves_domain?).and_return true
      allow(subject).to receive(:assert_not_in_maintenance_mode!)
    end

    it "checks the new server on its own address before moving the elastic IP", :aggregate_failures do
      subject.cutover

      expect(subject).to have_received(:serves_domain?).with("203.0.113.2").ordered
      expect(subject).to have_received(:flip_active_instance!).ordered
      expect(reread_phase).to eq "cutover"
    end

    context "when the new server does not serve the domain" do
      before { allow(subject).to receive(:serves_domain?).with("203.0.113.2").and_return false }

      it "does not move the elastic IP", :aggregate_failures do
        expect { subject.cutover }.to raise_error SystemExit
        expect(subject).not_to have_received :flip_active_instance!
        expect(reread_phase).to eq "copied"
      end
    end

    context "when a previous cutover did not finish" do
      before { Subspace::Upgrade::State.read("production").tap { |state| state["phase"] = "cutting_over" }.save }

      it "finishes moving the elastic IP", :aggregate_failures do
        subject.cutover

        expect(subject).to have_received(:check!).with(clean_plan: false)
        expect(subject).not_to have_received(:serves_domain?).with("203.0.113.2")
        expect(subject).to have_received(:flip_active_instance!)
        expect(reread_phase).to eq "cutover"
      end
    end
  end

  describe "#flip_active_instance!" do
    let(:terraform) { instance_double Subspace::Upgrade::Terraform, refresh: true }

    before do
      File.write "config/subspace/inventory.yml", <<~YML
        all:
          hosts:
            production-app1:
              ansible_host: 203.0.113.100
            production-app2:
              ansible_host: 203.0.113.2
          children:
            production:
              hosts:
                production-app1:
                production-app2:
      YML
      allow(subject).to receive(:apply!)
      allow(subject).to receive(:terraform).and_return terraform
      allow(terraform).to receive(:output).with("instances").and_return(
        "1" => { "hostname" => "production-app1", "public_ip" => "203.0.113.1" },
        "2" => { "hostname" => "production-app2", "public_ip" => "203.0.113.100" }
      )
    end

    it "points both hosts at their addresses after the elastic IP moves", :aggregate_failures do
      subject.send :flip_active_instance!, "2"

      hosts = Subspace::Inventory.read("config/subspace/inventory.yml").hosts
      expect(terraform).to have_received(:refresh).ordered
      expect(terraform).to have_received(:output).ordered
      expect(hosts["production-app1"].vars["ansible_host"]).to eq "203.0.113.1"
      expect(hosts["production-app2"].vars["ansible_host"]).to eq "203.0.113.100"
    end

    it "records cutting_over before terraform moves the elastic IP" do
      subject.send :flip_active_instance!, "2"

      expect(subject).to have_received(:apply!)
        .with({ "module.workhorse.aws_eip_association.eip_assoc" => %w[create update delete] }, starting: "cutting_over")
    end
  end

  describe "#abort_upgrade" do
    before do
      Subspace::Upgrade::State.read("production").tap do |state|
        state["phase"] = "copied"
        state["window_open"] = true
        state["to_slot"] = "2"
      end.save
      allow(subject).to receive(:ask).and_return "production"
      allow(subject).to receive(:start_application!)
      allow(subject).to receive(:remove_host!)
      allow(subject).to receive(:apply!)
    end

    it "puts the old server back and destroys the new slot", :aggregate_failures do
      subject.abort_upgrade

      expect(subject).to have_received(:start_application!).with("production-app1")
      expect(subject).to have_received(:maintenance_mode!).with(:off, "production-app1")
      expect(subject).to have_received(:apply!)
      expect(Subspace::Upgrade::State).not_to be_exist "production"
    end

    context "when the destroy is declined" do
      before { allow(subject).to receive(:apply!) { abort "Aborted." } }

      it "records that the old server is live again, so nothing can cut over", :aggregate_failures do
        expect { subject.abort_upgrade }.to raise_error SystemExit
        expect(reread_phase).to eq "aborting"
        expect(Subspace::Upgrade::State.read("production")["window_open"]).to be false
      end

      it "still takes the new server out of the inventory" do
        expect { subject.abort_upgrade }.to raise_error SystemExit
        expect(subject).to have_received(:remove_host!).with("production-app2")
      end

      it "does not restart the old server when run again" do
        expect { subject.abort_upgrade }.to raise_error SystemExit
        described_class.new("production", options).tap do |retry_upgrade|
          allow(retry_upgrade).to receive_messages(say: nil, ask: "production", check!: nil, remove_host!: nil, apply!: nil)
          allow(retry_upgrade).to receive(:start_application!)
          retry_upgrade.abort_upgrade

          expect(retry_upgrade).not_to have_received :start_application!
        end
      end
    end

    context "when a previous launch did not finish" do
      before do
        Subspace::Upgrade::State.read("production").tap do |state|
          state["phase"] = "launching"
          state["window_open"] = nil
        end.save
      end

      it "destroys the new slot without touching the old server", :aggregate_failures do
        subject.abort_upgrade

        expect(subject).to have_received(:check!).with(clean_plan: false)
        expect(subject).not_to have_received :start_application!
        expect(subject).to have_received(:apply!)
        expect(Subspace::Upgrade::State).not_to be_exist "production"
      end
    end

    context "when a previous cutover did not finish" do
      before { Subspace::Upgrade::State.read("production").tap { |state| state["phase"] = "cutting_over" }.save }

      it "refuses, since the new server may already be live", :aggregate_failures do
        expect { subject.abort_upgrade }.to raise_error SystemExit
        expect(subject).not_to have_received :start_application!
        expect(subject).not_to have_received :apply!
      end
    end
  end

  describe "#finalize" do
    before do
      Subspace::Upgrade::State.read("production").tap do |state|
        state["phase"] = "cutover"
        state["from_slot"] = "1"
      end.save
      allow(subject).to receive(:ask).and_return "production-app1"
      allow(subject).to receive(:backup_database!)
      allow(subject).to receive(:apply!)
      allow(subject).to receive(:remove_host!)
      allow(subject).to receive(:remove_from_group!)
    end

    it "records finalizing before terraform destroys the old slot", :aggregate_failures do
      subject.finalize

      expect(subject).to have_received(:backup_database!).with("production-app1")
      expect(subject).to have_received(:apply!)
        .with({ %(module.workhorse.aws_instance.single["1"]) => ["delete"] }, starting: "finalizing")
      expect(reread_phase).to eq "finalized"
    end

    context "when a previous finalize did not finish" do
      let(:main_tf) do
        <<~HCL
          module workhorse {
            source = "./modules/workhorse"

            instances = {
              "2" = {
                hostname      = "production-app2"
                ami           = "ami-0def"
                instance_type = "t3.medium"
                volume_size   = 20
              }
            }
            active_instance = "2"
            allow_instance_ssh = false
          }
        HCL
      end

      before do
        Subspace::Upgrade::State.read("production").tap do |state|
          state["phase"] = "finalizing"
          state["backup_path"] = "tmp/subspace/production-app1.dump"
        end.save
      end

      it "finishes destroying the old slot without backing it up again", :aggregate_failures do
        subject.finalize

        expect(subject).to have_received(:check!).with(clean_plan: false)
        expect(subject).not_to have_received :backup_database!
        expect(subject).to have_received(:apply!)
          .with({ %(module.workhorse.aws_instance.single["1"]) => ["delete"] }, starting: "finalizing")
        expect(subject).to have_received(:remove_host!).with("production-app1")
        expect(reread_phase).to eq "finalized"
      end
    end
  end

  describe "#copy_db" do
    it "advances to copied" do
      subject.copy_db

      expect(reread_phase).to eq "copied"
    end

    it "refuses to overwrite a populated destination on the first attempt" do
      subject.copy_db

      expect(subject).to have_received(:db_copy!).with("production-app1", "production-app2", overwrite: false)
    end

    context "when the source cannot ssh to the destination" do
      before { allow(subject).to receive(:check_db_copy!).and_raise SystemExit }

      it "fails before opening the window", :aggregate_failures do
        expect { subject.copy_db }.to raise_error SystemExit
        expect(subject).not_to have_received :maintenance_mode!
        expect(Subspace::Upgrade::State.read("production")["window_open"]).to be_nil
        expect(subject).to have_received :close_instance_ssh
      end
    end

    context "when a previous attempt started copying" do
      before { Subspace::Upgrade::State.read("production").tap { |state| state["db_copy_started"] = true }.save }

      it "overwrites whatever that attempt left on the destination" do
        subject.copy_db

        expect(subject).to have_received(:db_copy!).with("production-app1", "production-app2", overwrite: true)
      end
    end

    context "when the copy itself fails" do
      before { allow(subject).to receive(:db_copy!).and_raise "pg_restore failed" }

      it "still closes the ssh window", :aggregate_failures do
        expect { subject.copy_db }.to raise_error "pg_restore failed"
        expect(subject).to have_received :close_instance_ssh
        expect(reread_phase).to eq "prepared"
      end
    end

    context "when closing the ssh window fails" do
      before { allow(subject).to receive(:close_instance_ssh).and_raise "apply declined" }

      it "has already recorded the copy, so --cutover is not refused", :aggregate_failures do
        expect { subject.copy_db }.to raise_error "apply declined"
        expect(reread_phase).to eq "copied"
      end
    end
  end
end
