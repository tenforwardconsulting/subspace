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

    it "limits the run to both hosts the playbook has a play for" do
      subject.send :copy_letsencrypt!

      expect(subject).to have_received(:playbook).with(
        "upgrade_copy_letsencrypt",
        %w[production-app1 production-app2],
        "upgrade_host=production-app1",
        "letsencrypt_archive=#{archive}",
        "letsencrypt_destination=production-app2"
      )
    end

    it "does not leave the private keys on this machine" do
      subject.send :copy_letsencrypt!

      expect(File).not_to exist archive
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
  end

  describe "#copy_db" do
    it "advances to copied" do
      subject.copy_db

      expect(reread_phase).to eq "copied"
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
