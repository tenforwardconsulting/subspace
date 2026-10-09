require 'spec_helper'
require 'subspace/upgrade'
require 'tmpdir'

describe Subspace::Upgrade do
  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir dir do
        FileUtils.mkdir_p env_dir
        example.run
      end
    end
  end

  let(:env_dir) { "config/subspace/terraform/production" }
  let(:options) { double }

  def write_main_tf(source)
    File.write File.join(env_dir, "main.tf"), <<~HCL
      module workhorse {
        source = "#{source}"
      }
    HCL
  end

  def vendor(template)
    dir = File.join env_dir, "modules", template
    FileUtils.mkdir_p dir
    Subspace::Upgrade::ModuleManifest.write dir, template: template, repo: "repo", ref: "v2.0.0"
  end

  describe ".strategy_for" do
    context "with a vendored module that agrees with main.tf" do
      before do
        write_main_tf "./modules/workhorse"
        vendor "workhorse"
      end

      it "returns that template's strategy" do
        expect(described_class.strategy_for("production", options)).to be_a Subspace::Upgrade::Workhorse
      end
    end

    context "with a module referenced by git URL" do
      before { write_main_tf "github.com/tenforwardconsulting/terraform-subspace-workhorse?ref=v1.1.0" }

      it "reads the template from the source" do
        expect(described_class.strategy_for("production", options)).to be_a Subspace::Upgrade::Workhorse
      end
    end

    context "when the recorded state disagrees with main.tf" do
      before do
        write_main_tf "./modules/workhorse"
        Subspace::Upgrade::State.create("production", "template" => "oxenwagen").save
      end

      it "aborts" do
        expect { described_class.strategy_for("production", options) }
          .to raise_error(SystemExit).and output(/does not agree with itself/).to_stderr
      end
    end

    context "when a vendored module disagrees with main.tf" do
      before do
        write_main_tf "./modules/workhorse"
        vendor "oxenwagen"
      end

      it "aborts" do
        expect { described_class.strategy_for("production", options) }
          .to raise_error(SystemExit).and output(/does not agree with itself/).to_stderr
      end
    end

    context "when nothing names a template" do
      before { write_main_tf "./somewhere/else" }

      it "aborts" do
        expect { described_class.strategy_for("production", options) }
          .to raise_error(SystemExit).and output(/Could not determine/).to_stderr
      end
    end

    context "with a template subspace has no strategy for" do
      before { write_main_tf "./modules/barn" }

      it "aborts" do
        expect { described_class.strategy_for("production", options) }
          .to raise_error(SystemExit).and output(/Unknown terraform template 'barn'/).to_stderr
      end
    end
  end
end
