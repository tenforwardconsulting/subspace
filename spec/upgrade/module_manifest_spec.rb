require 'spec_helper'
require 'subspace/upgrade/module_manifest'
require 'tmpdir'
require 'digest'

describe Subspace::Upgrade::ModuleManifest do
  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir dir do
        example.run
      end
    end
  end

  let(:module_dir) { File.join Dir.pwd, "workhorse" }
  let(:bundled_dir) { described_class.bundled_dir("workhorse") }

  describe ".vendor" do
    it "copies every bundled file" do
      described_class.vendor "workhorse", module_dir

      expect(Dir.glob("**/*", base: module_dir).sort).to eq(
        (Dir.glob("**/*", base: bundled_dir) + ["module.yml"]).sort
      )
    end

    it "writes the template, subspace version and a checksum per file" do
      described_class.vendor "workhorse", module_dir

      expected_checksums = Dir.glob("*", base: bundled_dir).sort.to_h do |file|
        [file, Digest::SHA256.file(File.join(bundled_dir, file)).hexdigest]
      end

      expect(described_class.read(module_dir)).to eq({
        "template" => "workhorse",
        "version" => Subspace::VERSION,
        "checksums" => expected_checksums
      })
    end
  end

  describe ".modified_files" do
    before { described_class.vendor "workhorse", module_dir }

    context "with an untouched module" do
      it "is empty" do
        expect(described_class.modified_files(module_dir)).to eq []
      end
    end

    context "with an edited file" do
      before { File.write File.join(module_dir, "variables.tf"), File.read(File.join(module_dir, "variables.tf")) + "# edit\n" }

      it "lists an edited file" do
        expect(described_class.modified_files(module_dir)).to eq ["variables.tf"]
      end
    end

    context "with an added file" do
      before { File.write File.join(module_dir, "extra.tf"), "" }

      it "lists an added file" do
        expect(described_class.modified_files(module_dir)).to eq ["extra.tf"]
      end
    end

    context "with a deleted file" do
      before { FileUtils.rm File.join(module_dir, "route53.tf") }

      it "lists a deleted file" do
        expect(described_class.modified_files(module_dir)).to eq ["route53.tf"]
      end
    end

    context "with a manifest from a git clone" do
      before do
        described_class.write module_dir, template: "workhorse", repo: "https://example.com/workhorse.git", ref: "v2.0.0"
      end

      it "lists every file" do
        expect(described_class.modified_files(module_dir)).to eq described_class.checksums(module_dir).keys
      end
    end
  end
end
