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
    allow(subject).to receive(:record_site_response!)
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
      allow(subject).to receive(:check_subspace_key!)
      allow(subject).to receive(:assert_clean_git_tree!)
      allow(subject).to receive(:confirm_database_backup!)
      allow(subject).to receive(:apply!)
      allow(subject).to receive(:update_inventory!)
      allow(subject).to receive(:add_to_group!)
    end

    it "records launching before terraform creates the new slot", :aggregate_failures do
      subject.launch

      expect(subject).to have_received(:check_subspace_key!)
      expect(subject).to have_received(:apply!).with({
        %(module.workhorse.aws_instance.single["2"]) => ["create"],
        "module.workhorse.aws_security_group.single" => ["update"]
      }, starting: "launching")
      expect(reread_phase).to eq "launched"
    end

    it "opens ssh between the servers in the same apply, so copy_db does not have to" do
      subject.launch

      expect(subject.config.allow_instance_ssh).to eq true
    end

    it "adds the new slot with the old slot's size and the target ami" do
      subject.launch

      expect(subject.config.instances["2"]).to eq(
        "hostname" => %("production-app2"),
        "ami" => %("ami-0new"),
        "instance_type" => %("t3.medium"),
        "volume_size" => "20"
      )
    end

    it "records both slots before terraform runs", :aggregate_failures do
      subject.launch

      state = Subspace::Upgrade::State.read "production"
      expect(state["from_slot"]).to eq "1"
      expect(state["to_slot"]).to eq "2"
      expect(state["from_hostname"]).to eq "production-app1"
      expect(state["to_hostname"]).to eq "production-app2"
      expect(state["from_ami"]).to eq "ami-0abc"
      expect(state["to_ami"]).to eq "ami-0new"
      expect(state["ubuntu_release"]).to eq "noble"
    end

    context "when the slot keys have gaps" do
      let(:main_tf) do
        <<~HCL
          module workhorse {
            source = "./modules/workhorse"

            instances = {
              "3" = {
                hostname      = "production-app1"
                ami           = "ami-0abc"
                instance_type = "t3.medium"
                volume_size   = 20
              }
            }
            active_instance = "3"
            allow_instance_ssh = false
          }
        HCL
      end

      it "takes the slot after the highest key, and names the host from the active one", :aggregate_failures do
        subject.launch

        state = Subspace::Upgrade::State.read "production"
        expect(state["to_slot"]).to eq "4"
        expect(state["to_hostname"]).to eq "production-app2"
      end
    end

    context "when the next hostname is already taken" do
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

      it "refuses before recording anything", :aggregate_failures do
        expect { subject.launch }.to raise_error SystemExit, /Could not derive a free hostname/
        expect(Subspace::Upgrade::State.read("production")["to_slot"]).to be_nil
        expect(subject).not_to have_received :apply!
      end
    end

    context "when the active hostname does not end in a number" do
      let(:main_tf) do
        <<~HCL
          module workhorse {
            source = "./modules/workhorse"

            instances = {
              "1" = {
                hostname      = "production-app"
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

      it "refuses" do
        expect { subject.launch }.to raise_error SystemExit, /Could not derive a free hostname/
      end
    end

    context "without --ami" do
      let(:options) { double ami: nil, ubuntu_release: "noble" }

      before do
        allow(subject).to receive(:project_name).and_return "test_project"
        allow(Subspace::Ami).to receive(:latest).and_return "ami-0latest"
      end

      it "launches the latest ami for the release", :aggregate_failures do
        subject.launch

        expect(Subspace::Ami).to have_received(:latest).with(release: "noble", profile: "subspace-test_project")
        expect(Subspace::Upgrade::State.read("production")["to_ami"]).to eq "ami-0latest"
      end

      context "or --ubuntu-release" do
        let(:options) { double ami: nil, ubuntu_release: nil }

        it "records the default release" do
          subject.launch

          expect(Subspace::Upgrade::State.read("production")["ubuntu_release"]).to eq Subspace::Ami::DEFAULT_RELEASE
        end
      end
    end

    context "with --ami and no --ubuntu-release" do
      let(:options) { double ami: "ami-0new", ubuntu_release: nil }

      it "does not claim a release it cannot know", :aggregate_failures do
        subject.launch

        expect(Subspace::Upgrade::State.read("production")["ubuntu_release"]).to be_nil
        expect(Subspace::Upgrade::State.read("production")["to_ami"]).to eq "ami-0new"
      end
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
        expect(subject).not_to have_received :check_subspace_key!
        expect(subject).to have_received(:apply!).with({
          %(module.workhorse.aws_instance.single["2"]) => ["create"],
          "module.workhorse.aws_security_group.single" => ["update"]
        }, starting: "launching")
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
      allow(subject).to receive(:join_tailnet!)
      allow(subject).to receive(:write_capistrano_stage!)
    end

    it "advances to prepared" do
      subject.provision

      expect(reread_phase).to eq "prepared"
    end

    it "joins the tailnet before writing the stage, so the stage gets the tailscale address", :aggregate_failures do
      subject.provision

      expect(subject).to have_received(:provision!).with("production-app2").ordered
      expect(subject).to have_received(:join_tailnet!).with("production-app2").ordered
      expect(subject).to have_received(:write_capistrano_stage!).ordered
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

    it "copies the base stage as the base stage, pointing its server at the new host" do
      subject.send :write_capistrano_stage!

      expect(File.read("config/deploy/production_upgrade.rb")).to eq <<~RUBY
        # Generated by Subspace from config/deploy/production.rb
        set :stage, :production
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

    describe "#promote_capistrano_stage!" do
      let(:promoted) do
        <<~RUBY
          # Tailscale IP:
          server '203.0.113.2', user: 'deploy', roles: %w{web app db}, ssh_options: { forward_agent: true }
          # server '3.137.61.218', user: 'deploy', roles: %w{web app db}
          set :rails_env, "production"
          set :branch, "production"
        RUBY
      end

      before { subject.send :write_capistrano_stage! }

      it "points the base stage at the new host and drops the upgrade stage", :aggregate_failures do
        subject.send :promote_capistrano_stage!

        expect(File.read("config/deploy/production.rb")).to eq promoted
        expect(File).not_to exist "config/deploy/production_upgrade.rb"
      end

      it "can be run again by an unfinished cutover" do
        2.times { subject.send :promote_capistrano_stage! }

        expect(File.read("config/deploy/production.rb")).to eq promoted
      end
    end
  end

  describe "#cutover" do
    before do
      Subspace::Upgrade::State.read("production").tap { |state| state["phase"] = "copied" }.save
      allow(subject).to receive(:to_public_ip).and_return "203.0.113.2"
      allow(subject).to receive(:flip_active_instance!)
      allow(subject).to receive(:promote_capistrano_stage!)
      allow(subject).to receive(:serves_domain?).and_return true
      allow(subject).to receive(:assert_not_in_maintenance_mode!)
    end

    it "checks the new server on its own address before moving the elastic IP", :aggregate_failures do
      subject.cutover

      expect(subject).to have_received(:serves_domain?).with("203.0.113.2").ordered
      expect(subject).to have_received(:flip_active_instance!).ordered
      expect(subject).to have_received(:promote_capistrano_stage!).ordered
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

  describe "#join_tailnet!" do
    before do
      File.write "config/subspace/inventory.yml", <<~YML
        all:
          hosts:
            production-app2:
              ansible_host: 203.0.113.2
          children:
            production:
              hosts:
                production-app2:
      YML
      allow(subject).to receive(:ansible_playbook).and_return true
      allow(subject).to receive(:learn_host_key!)
    end

    def reread_address
      Subspace::Inventory.read("config/subspace/inventory.yml").hosts["production-app2"].vars["ansible_host"]
    end

    context "when the server has not joined yet" do
      before { allow(subject).to receive(:tailscale_ip).and_return nil, "100.80.224.44" }

      it "joins, then addresses it by its tailscale IP", :aggregate_failures do
        subject.send :join_tailnet!, "production-app2"

        expect(subject).to have_received(:ansible_playbook)
          .with("production.yml", "--limit", "production-app2", "--tags", "tailscale_reauth")
        expect(reread_address).to eq "100.80.224.44"
        expect(subject).to have_received(:learn_host_key!).with("100.80.224.44")
      end
    end

    context "when the server is already on the tailnet" do
      before { allow(subject).to receive(:tailscale_ip).and_return "100.80.224.44" }

      it "does not reauth, which could hand out a new address", :aggregate_failures do
        subject.send :join_tailnet!, "production-app2"

        expect(subject).not_to have_received :ansible_playbook
        expect(reread_address).to eq "100.80.224.44"
      end
    end

    context "when joining fails" do
      before do
        allow(subject).to receive(:tailscale_ip).and_return nil
        allow(subject).to receive(:ansible_playbook).and_return false
      end

      it "aborts, leaving the public address", :aggregate_failures do
        expect { subject.send :join_tailnet!, "production-app2" }.to raise_error SystemExit, /tailnet failed/
        expect(reread_address).to eq "203.0.113.2"
      end
    end
  end

  describe "#tailscale_ip" do
    it "reads the address from ansible's one-line output" do
      allow(Open3).to receive(:capture3).and_return [
        "production-app2 | CHANGED | rc=0 | (stdout) 100.80.224.44\n", "", instance_double(Process::Status, success?: true)
      ]

      expect(subject.send(:tailscale_ip, "production-app2")).to eq "100.80.224.44"
    end

    it "is nil when tailscale is not up" do
      allow(Open3).to receive(:capture3).and_return [
        "production-app2 | FAILED | rc=1 | (stdout) \n", "", instance_double(Process::Status, success?: false)
      ]

      expect(subject.send(:tailscale_ip, "production-app2")).to be_nil
    end
  end

  describe "#flip_active_instance!" do
    let(:inventory) do
      <<~YML
        all:
          hosts:
            production-app1:
              ansible_host: 100.64.0.1
            production-app2:
              ansible_host: 100.64.0.2
          children:
            production:
              hosts:
                production-app1:
                production-app2:
      YML
    end

    before do
      File.write "config/subspace/inventory.yml", inventory
      allow(subject).to receive(:apply!)
    end

    it "leaves the inventory on the tailscale addresses" do
      subject.send :flip_active_instance!, "2"

      expect(File.read("config/subspace/inventory.yml")).to eq inventory
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

      expect(subject).to have_received(:check!).with(clean_plan: false)
      expect(subject).to have_received(:start_application!).with("production-app1")
      expect(subject).to have_received(:maintenance_mode!).with(:off, "production-app1")
      expect(subject).to have_received(:apply!)
      expect(Subspace::Upgrade::State).not_to be_exist "production"
    end

    it "closes ssh between the servers in the same apply that destroys the new slot", :aggregate_failures do
      subject.abort_upgrade

      expect(subject).to have_received(:apply!).with({
        %(module.workhorse.aws_instance.single["2"]) => ["delete"],
        "module.workhorse.aws_security_group.single" => ["update"]
      }, starting: "aborting")
      expect(subject.config.allow_instance_ssh).to eq false
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
      expect(subject).to have_received(:apply!).with({
        %(module.workhorse.aws_instance.single["1"]) => ["delete"],
        "module.workhorse.aws_security_group.single" => ["update"]
      }, starting: "finalizing")
      expect(reread_phase).to eq "finalized"
    end

    it "closes ssh between the servers in the same apply that destroys the old slot" do
      subject.finalize

      expect(subject.config.allow_instance_ssh).to eq false
    end

    it "drops the old slot and takes the new host out of the upgrade group", :aggregate_failures do
      subject.finalize

      expect(subject.config.instances.keys).to eq ["2"]
      expect(subject).to have_received(:remove_host!).with("production-app1")
      expect(subject).to have_received(:remove_from_group!).with("production-app2", "upgrade")
    end

    context "when the confirmation is not the old hostname" do
      before { allow(subject).to receive(:ask).and_return "y" }

      it "refuses before backing up or destroying anything", :aggregate_failures do
        expect { subject.finalize }.to raise_error SystemExit
        expect(subject).not_to have_received :backup_database!
        expect(subject).not_to have_received :apply!
        expect(reread_phase).to eq "cutover"
      end
    end

    context "when the backup fails" do
      before { allow(subject).to receive(:backup_database!) { abort "empty" } }

      it "does not destroy the old slot", :aggregate_failures do
        expect { subject.finalize }.to raise_error SystemExit
        expect(subject).not_to have_received :apply!
        expect(reread_phase).to eq "cutover"
      end
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
        expect(subject).to have_received(:apply!).with({
          %(module.workhorse.aws_instance.single["1"]) => ["delete"],
          "module.workhorse.aws_security_group.single" => ["update"]
        }, starting: "finalizing")
        expect(subject).to have_received(:remove_host!).with("production-app1")
        expect(reread_phase).to eq "finalized"
      end
    end
  end

  describe "#backup_database!" do
    let(:dump) { "pg_dump output" }

    before do
      allow(subject).to receive(:playbook) do |*, db_dump_dest:, **|
        File.write db_dump_dest, dump
        true
      end
    end

    it "dumps the old server's database locally and records it", :aggregate_failures do
      subject.send :backup_database!, "production-app1"

      state = Subspace::Upgrade::State.read "production"
      expect(subject).to have_received(:playbook)
        .with("db_dump", "production-app1", upgrade_host: "production-app1", db_dump_dest: File.expand_path(state["backup_path"]))
      expect(state["backup_path"]).to match %r{\Atmp/subspace/production-production-app1-\d{8}T\d{6}Z\.dump\z}
      expect(state["backup_bytes"]).to eq dump.bytesize
      expect(state["backup_sha256"]).to eq Digest::SHA256.hexdigest(dump)
    end

    context "when the dump is empty" do
      let(:dump) { "" }

      it "refuses to continue", :aggregate_failures do
        expect { subject.send :backup_database!, "production-app1" }.to raise_error SystemExit, /missing or empty/
        expect(Subspace::Upgrade::State.read("production")["backup_path"]).to be_nil
      end
    end

    context "when the dump playbook fails" do
      before { allow(subject).to receive(:playbook).and_return false }

      it "refuses to continue" do
        expect { subject.send :backup_database!, "production-app1" }.to raise_error SystemExit, /db_dump failed/
      end
    end
  end

  describe "#record_site_response!" do
    let(:path) { File.expand_path "tmp/subspace/production-site-response" }

    before do
      allow(subject).to receive(:record_site_response!).and_call_original
      allow(subject).to receive(:playbook) do |*, site_response_file:, **|
        File.write site_response_file, "302 https://example.com/users/sign_in\n"
        true
      end
    end

    it "records how the old server answers, for the new one to match", :aggregate_failures do
      subject.send :record_site_response!

      expect(subject).to have_received(:playbook)
        .with("upgrade_verify_tls", "production-app1", upgrade_host: "production-app1", site_response_file: path)
      expect(Subspace::Upgrade::State.read("production")["site_response"]).to eq "302 https://example.com/users/sign_in"
      expect(File).not_to exist path
    end

    context "when a previous attempt recorded it" do
      before { Subspace::Upgrade::State.read("production").tap { |state| state["site_response"] = "200" }.save }

      it "keeps it, since the old server may be showing the maintenance page now", :aggregate_failures do
        subject.send :record_site_response!

        expect(subject).not_to have_received :playbook
        expect(Subspace::Upgrade::State.read("production")["site_response"]).to eq "200"
      end
    end
  end

  describe "#serves_domain?" do
    before do
      Subspace::Upgrade::State.read("production").tap { |state| state["site_response"] = "200" }.save
      allow(subject).to receive(:playbook).and_return true
    end

    it "holds the new server to the recorded response" do
      subject.send :serves_domain?, "203.0.113.2"

      expect(subject).to have_received(:playbook).with("upgrade_verify_tls", "production-app2",
        upgrade_host: "production-app2", verify_address: "203.0.113.2", expected_response: "200")
    end
  end

  describe "#copy_db" do
    it "advances to copied, leaving ssh between the servers for --finalize to close", :aggregate_failures do
      subject.copy_db

      expect(reread_phase).to eq "copied"
      expect(subject).not_to have_received :close_instance_ssh
    end

    it "opens ssh between the servers when it has been closed since --launch" do
      subject.copy_db

      expect(subject).to have_received :open_instance_ssh!
    end

    context "when --launch left ssh between the servers open" do
      let(:main_tf) { super().sub("allow_instance_ssh = false", "allow_instance_ssh = true") }

      it "copies without an apply" do
        subject.copy_db

        expect(subject).not_to have_received :open_instance_ssh!
      end
    end

    it "refuses to overwrite a populated destination on the first attempt", :aggregate_failures do
      subject.copy_db

      expect(subject).to have_received(:check_db_copy!).with("production-app1", "production-app2", overwrite: false)
      expect(subject).to have_received(:db_copy!).with("production-app1", "production-app2", overwrite: false)
    end

    it "records the site's response and checks the destination before opening the window", :aggregate_failures do
      subject.copy_db

      expect(subject).to have_received(:record_site_response!).ordered
      expect(subject).to have_received(:check_db_copy!).ordered
      expect(subject).to have_received(:maintenance_mode!).with(:on, "production-app1").ordered
    end

    context "when the source cannot ssh to the destination" do
      before { allow(subject).to receive(:check_db_copy!).and_raise SystemExit }

      it "fails before opening the window", :aggregate_failures do
        expect { subject.copy_db }.to raise_error SystemExit
        expect(subject).not_to have_received :maintenance_mode!
        expect(Subspace::Upgrade::State.read("production")["window_open"]).to be_nil
      end
    end

    context "when a previous attempt started copying" do
      before { Subspace::Upgrade::State.read("production").tap { |state| state["db_copy_started"] = true }.save }

      it "overwrites whatever that attempt left on the destination", :aggregate_failures do
        subject.copy_db

        expect(subject).to have_received(:check_db_copy!).with("production-app1", "production-app2", overwrite: true)
        expect(subject).to have_received(:db_copy!).with("production-app1", "production-app2", overwrite: true)
      end
    end

    context "when the copy itself fails" do
      before { allow(subject).to receive(:db_copy!).and_raise "pg_restore failed" }

      it "stays prepared" do
        expect { subject.copy_db }.to raise_error "pg_restore failed"
        expect(reread_phase).to eq "prepared"
      end
    end
  end
end
