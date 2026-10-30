require 'spec_helper'
require 'commander'
require 'subspace/commands/base'
require 'subspace/commands/init'
require 'tmpdir'

describe Subspace::Commands::Init do
  describe "#vendor_terraform_module" do
    around do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        example.run
      end
    end
    let(:dir) { @dir }
    subject { described_class.allocate }
    before do
      allow(subject).to receive(:dest_dir).and_return dir
      allow(subject).to receive(:say)
      allow(subject).to receive(:system) { |*args| FileUtils.mkdir_p args.last }
      subject.instance_variable_set :@env, "dev"
    end

    context "with the workhorse template" do
      before { subject.instance_variable_set :@template, "workhorse" }

      it "copies the bundled module without cloning", :aggregate_failures do
        expect(subject.send(:vendor_terraform_module)).to eq "./modules/workhorse"
        expect(Subspace::Upgrade::ModuleManifest.read(File.join(dir, "terraform/dev/modules/workhorse"))["version"]).to eq Subspace::VERSION
        expect(subject).not_to have_received(:system)
      end
    end

    context "with the oxenwagen template" do
      before { subject.instance_variable_set :@template, "oxenwagen" }

      it "copies the bundled module without cloning", :aggregate_failures do
        expect(subject.send(:vendor_terraform_module)).to eq "./modules/oxenwagen"
        expect(Subspace::Upgrade::ModuleManifest.read(File.join(dir, "terraform/dev/modules/oxenwagen"))["version"]).to eq Subspace::VERSION
        expect(subject).not_to have_received(:system)
      end
    end

    context "with a template that is not a vendored module" do
      before { subject.instance_variable_set :@template, "s3_backend" }

      it "copies nothing", :aggregate_failures do
        expect(subject.send(:vendor_terraform_module)).to be nil
        expect(Dir.exist?(File.join(dir, "terraform/dev/modules"))).to be false
      end
    end
  end
end
