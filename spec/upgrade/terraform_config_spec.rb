require 'spec_helper'
require 'subspace/upgrade'
require 'tmpdir'

describe Subspace::Upgrade::TerraformConfig do
  MAIN_TF = <<~HCL
    module workhorse {
      source = "./modules/workhorse"
      project_name = "my_project"
      instance_user = "ubuntu"

      instances = {
        "1" = {
          hostname      = "production-app1"
          ami           = "ami-0abc"
          instance_type = "t3.medium"
          volume_size   = 20
        }
      }
      active_instance = "1"
    }
  HCL

  around do |example|
    Dir.mktmpdir do |dir|
      @path = File.join dir, "main.tf"
      File.write @path, MAIN_TF
      example.run
    end
  end

  subject { described_class.new @path }

  it "reads the module name" do
    expect(subject.module_name).to eq "workhorse"
  end

  it "reads the instances map, keeping literals as written" do
    expect(subject.instances).to eq(
      "1" => {
        "hostname" => '"production-app1"',
        "ami" => '"ami-0abc"',
        "instance_type" => '"t3.medium"',
        "volume_size" => "20",
      }
    )
  end

  it "reads the hostname for a slot" do
    expect(subject.hostname_for("1")).to eq "production-app1"
  end

  it "reads and writes active_instance" do
    expect(subject.active_instance).to eq "1"
    subject.active_instance = "2"
    subject.save
    expect(described_class.new(@path).active_instance).to eq "2"
  end

  it "adds allow_instance_ssh when the config does not mention it" do
    expect(subject.allow_instance_ssh).to eq false
    subject.allow_instance_ssh = true
    subject.save

    reread = described_class.new @path
    expect(reread.allow_instance_ssh).to eq true
    expect(reread.active_instance).to eq "1"
    expect(reread.instances.keys).to eq ["1"]
  end

  it "toggles allow_instance_ssh back off without duplicating it" do
    subject.allow_instance_ssh = true
    subject.allow_instance_ssh = false
    subject.save
    expect(File.read(@path).scan("allow_instance_ssh").size).to eq 1
    expect(described_class.new(@path).allow_instance_ssh).to eq false
  end

  it "adds a slot, copying literals verbatim" do
    subject.add_instance "2", "hostname" => '"production-app2"',
                              "ami" => '"ami-0def"',
                              "instance_type" => '"t3.medium"',
                              "volume_size" => "20"
    subject.save

    reread = described_class.new @path
    expect(reread.instances.keys).to eq %w[1 2]
    expect(reread.hostname_for("2")).to eq "production-app2"
    expect(reread.instances["2"]["volume_size"]).to eq "20"
    expect(reread.active_instance).to eq "1"
  end

  it "refuses to add a slot that already exists" do
    expect { subject.add_instance "1", "hostname" => '"x"' }.to raise_error(/already defined/)
  end

  it "removes a slot" do
    subject.add_instance "2", "hostname" => '"production-app2"',
                              "ami" => '"ami-0def"',
                              "instance_type" => '"t3.medium"',
                              "volume_size" => "20"
    subject.save

    config = described_class.new @path
    config.remove_instance "1"
    config.save

    expect(described_class.new(@path).instances.keys).to eq ["2"]
  end

  it "refuses to remove a slot that does not exist" do
    expect { subject.remove_instance "9" }.to raise_error(/no slot 9/)
  end

  it "leaves the rest of the file alone" do
    subject.add_instance "2", "hostname" => '"production-app2"',
                              "ami" => '"ami-0def"',
                              "instance_type" => '"t3.medium"',
                              "volume_size" => "20"
    subject.save
    expect(File.read(@path)).to include %(source = "./modules/workhorse")
    expect(File.read(@path)).to include %(project_name = "my_project")
  end

  it "reverts to the file as read", :aggregate_failures do
    subject.active_instance = "2"
    subject.save
    subject.revert

    expect(File.read(@path)).to eq MAIN_TF
    expect(subject.active_instance).to eq "1"
  end

  it "reverts to the last applied source", :aggregate_failures do
    subject.active_instance = "2"
    subject.mark_applied
    subject.allow_instance_ssh = true
    subject.save
    subject.revert

    expect(described_class.new(@path).active_instance).to eq "2"
    expect(described_class.new(@path).allow_instance_ssh).to eq false
  end

  it "raises a useful error on a v1 config with no instances map" do
    File.write @path, %(module workhorse {\n  instance_ami = "ami-0abc"\n}\n)
    expect { described_class.new(@path).instances }.to raise_error(/at least v2.0.0/)
  end
end
