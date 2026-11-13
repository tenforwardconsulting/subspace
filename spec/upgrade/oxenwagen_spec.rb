require 'spec_helper'
require 'subspace/upgrade'
require 'tmpdir'

describe Subspace::Upgrade::Oxenwagen do
  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir dir do
        FileUtils.mkdir_p "config/subspace/terraform/production"
        example.run
      end
    end
  end

  let(:old_web_tf) do
    <<~HCL
      "1" = {
        hostname      = "production-web1"
        ami           = "ami-0abc"
        instance_type = "t3.medium"
        volume_size   = 20
        subnet_id     = "subnet-0aaa"
      }
      "2" = {
        hostname      = "production-web2"
        ami           = "ami-0abc"
        instance_type = "t3.large"
        volume_size   = 40
        subnet_id     = "subnet-0bbb"
      }
    HCL
  end

  let(:new_web_tf) do
    <<~HCL
      "3" = {
        hostname      = "production-web3"
        ami           = "ami-0new"
        instance_type = "t3.medium"
        volume_size   = 20
        subnet_id     = "subnet-0aaa"
      }
      "4" = {
        hostname      = "production-web4"
        ami           = "ami-0new"
        instance_type = "t3.large"
        volume_size   = 40
        subnet_id     = "subnet-0bbb"
      }
    HCL
  end

  let(:old_worker_tf) do
    <<~HCL
      "1" = {
        hostname      = "production-worker1"
        ami           = "ami-0abc"
        instance_type = "t3.medium"
        volume_size   = 20
        subnet_id     = "subnet-0aaa"
      }
    HCL
  end

  let(:new_worker_tf) do
    <<~HCL
      "2" = {
        hostname      = "production-worker2"
        ami           = "ami-0new"
        instance_type = "t3.medium"
        volume_size   = 20
        subnet_id     = "subnet-0aaa"
      }
    HCL
  end

  let(:web_tf) { old_web_tf + new_web_tf }
  let(:worker_tf) { old_worker_tf + new_worker_tf }
  let(:lb_instances) { %w[1 2] }

  let(:main_tf) do
    <<~HCL
      module oxenwagen {
        source = "./modules/oxenwagen"
        aws_region = "us-west-2"

        web_instances = {
      #{web_tf}
        }
        worker_instances = {
      #{worker_tf}
        }
        lb_instances = #{lb_instances.inspect}
      }

      output "inventory" {
        value = module.oxenwagen.inventory
      }
      output "web_instances" {
        value = module.oxenwagen.web_instances
      }
      output "worker_instances" {
        value = module.oxenwagen.worker_instances
      }
      output "lb_instances" {
        value = module.oxenwagen.lb_instances
      }
      output "lb_target_group_arn" {
        value = module.oxenwagen.lb_target_group_arn
      }
    HCL
  end

  let(:count_based_main_tf) do
    <<~HCL
      module oxenwagen {
        source = "github.com/tenforwardconsulting/terraform-subspace-oxenwagen?ref=v2.4.1"

        instance_ami = "ami-0abc"
        web_instance_type = "t3.small"
        web_instance_count = 2
        worker_instance_type = "t3.medium"
        worker_instance_count = 1
        worker_volume_size = 100
      }

      output "inventory" {
        value = module.oxenwagen
      }
    HCL
  end

  let(:inventory_yml) do
    <<~YML
      all:
        hosts:
          production-web1:
            ansible_host: 100.64.0.1
            hostname: production-web1
          production-web2:
            ansible_host: 100.64.0.2
            hostname: production-web2
          production-worker1:
            ansible_host: 100.64.0.5
            hostname: production-worker1
          production-web3:
            ansible_host: 100.64.0.3
            hostname: production-web3
          production-web4:
            ansible_host: 100.64.0.4
            hostname: production-web4
          production-worker2:
            ansible_host: 100.64.0.6
            hostname: production-worker2
        children:
          production:
            hosts:
              production-web1:
              production-web2:
              production-worker1:
              production-web3:
              production-web4:
              production-worker2:
          production_web:
            hosts:
              production-web1:
              production-web2:
              production-web3:
              production-web4:
          production_worker:
            hosts:
              production-worker1:
              production-worker2:
          upgrade:
            hosts:
              production-web3:
              production-web4:
              production-worker2:
    YML
  end

  let(:recorded_slots) do
    {
      "to_ami" => "ami-0new",
      "web_slots" => {
        "1" => { "to_slot" => "3", "from_hostname" => "production-web1", "to_hostname" => "production-web3" },
        "2" => { "to_slot" => "4", "from_hostname" => "production-web2", "to_hostname" => "production-web4" },
      },
      "worker_slots" => {
        "1" => { "to_slot" => "2", "from_hostname" => "production-worker1", "to_hostname" => "production-worker2" },
      },
    }
  end

  let(:phase) { "prepared" }
  let(:lb_record) { {} }
  let(:upgrade) { { "template" => "oxenwagen", "phase" => phase }.merge(recorded_slots, lb_record) }

  let(:terraform_outputs) do
    {
      "inventory" => {
        "hostnames" => %w[production-web1 production-web2 production-web3 production-web4 production-worker1 production-worker2],
        "ip_addresses" => %w[100.64.0.1 100.64.0.2 203.0.113.3 203.0.113.4 100.64.0.5 203.0.113.6],
        "groups" => ["production production_web"] * 4 + ["production production_worker"] * 2,
        "users" => ["ubuntu"] * 6,
      },
      "web_instances" => {
        "1" => { "id" => "i-0web1" },
        "2" => { "id" => "i-0web2" },
        "3" => { "id" => "i-0web3" },
        "4" => { "id" => "i-0web4" },
      },
      "lb_target_group_arn" => "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/production/0abc",
    }
  end

  let(:terraform) { instance_double Subspace::Upgrade::Terraform }
  let(:target_health) { { "i-0web3" => "healthy", "i-0web4" => "healthy" } }
  let(:options) { double ami: "ami-0new", ubuntu_release: "noble" }

  let(:stage_header) { "# Generated by Subspace from config/deploy/production.rb\nset :stage, :production\n" }
  let(:new_server_lines) do
    <<~RUBY
      server '100.64.0.3', user: 'deploy', roles: %w{web app} # production-web3
      server '100.64.0.4', user: 'deploy', roles: %w{web app} # production-web4
      server '100.64.0.6', user: 'deploy', roles: %w{app db} # production-worker2
    RUBY
  end

  subject { described_class.new "production", options }

  before do
    File.write "config/subspace/terraform/production/main.tf", main_tf
    File.write "config/subspace/inventory.yml", inventory_yml
    allow(subject).to receive(:say)
    allow(subject).to receive(:ask).and_return "y"
    allow(subject).to receive(:check!)
    allow(subject).to receive(:playbook).and_return true
    allow(subject).to receive(:sleep)
    allow(subject).to receive(:terraform).and_return terraform
    allow(terraform).to receive(:output) { |name| terraform_outputs.fetch name }
    allow(Subspace::Elb).to receive(:target_health).and_return target_health
    allow(Subspace::Ec2).to receive(:elastic_ip_headroom).and_return 10
  end

  def reread_phase
    Subspace::Upgrade::State.read("production").phase
  end

  def reread_state
    Subspace::Upgrade::State.read("production").data
  end

  describe "the bundled oxenwagen module" do
    let(:sources) { Dir[File.expand_path("../../terraform/modules/oxenwagen/*.tf", __dir__)].map { |file| File.read file }.join }

    it "declares every required module variable", :aggregate_failures do
      described_class::REQUIRED_MODULE_VARIABLES.each do |name|
        expect(sources).to match(/^variable\s+"?#{name}"?\s/)
      end
    end

    it "outputs everything the root re-exports", :aggregate_failures do
      described_class::REQUIRED_ROOT_OUTPUTS.each do |name|
        expect(sources).to match(/^output\s+"#{name}"\s*\{/)
      end
    end

    it "keys every instance resource by slot rather than by count", :aggregate_failures do
      expect(sources).to match(/resource "aws_instance" "web" \{\n\s*for_each\s+= var\.web_instances/)
      expect(sources).to match(/resource "aws_instance" "worker" \{\n\s*for_each\s+= var\.worker_instances/)
      expect(sources).not_to match(/count\.index/)
    end

    it "guards the load balancer against an empty or unknown target set", :aggregate_failures do
      expect(sources).to include "length(var.lb_instances) > 0"
      expect(sources).to include "setsubtract(toset(var.lb_instances), keys(var.web_instances))"
    end
  end

  describe "#launch" do
    let(:web_tf) { old_web_tf }
    let(:worker_tf) { old_worker_tf }
    let(:upgrade) { { "template" => "oxenwagen", "phase" => "initialized" } }

    let(:new_slot_creates) do
      {
        %(module.oxenwagen.aws_instance.web["3"]) => ["create"],
        %(module.oxenwagen.aws_instance.web["4"]) => ["create"],
        %(module.oxenwagen.aws_eip.web["3"]) => ["create"],
        %(module.oxenwagen.aws_eip.web["4"]) => ["create"],
        %(module.oxenwagen.aws_eip_association.eip_assoc["3"]) => ["create"],
        %(module.oxenwagen.aws_eip_association.eip_assoc["4"]) => ["create"],
        %(module.oxenwagen.aws_route53_record.web["3"]) => ["create"],
        %(module.oxenwagen.aws_route53_record.web["4"]) => ["create"],
        %(module.oxenwagen.aws_instance.worker["2"]) => ["create"],
        %(module.oxenwagen.aws_eip.worker["2"]) => ["create"],
        %(module.oxenwagen.aws_eip_association.worker_eip_assoc["2"]) => ["create"],
        %(module.oxenwagen.aws_route53_record.worker["2"]) => ["create"],
      }
    end

    let(:inventory_yml) do
      <<~YML
        all:
          hosts:
            production-web1:
              ansible_host: 100.64.0.1
              hostname: production-web1
            production-web2:
              ansible_host: 100.64.0.2
              hostname: production-web2
            production-worker1:
              ansible_host: 100.64.0.5
              hostname: production-worker1
          children:
            production:
              hosts:
                production-web1:
                production-web2:
                production-worker1:
            production_web:
              hosts:
                production-web1:
                production-web2:
            production_worker:
              hosts:
                production-worker1:
      YML
    end

    before do
      Subspace::Upgrade::State.create("production", upgrade).save
      allow(subject).to receive(:check_subspace_key!)
      allow(subject).to receive(:assert_clean_git_tree!)
      allow(subject).to receive(:apply!)
    end

    it "adds a new slot for every web and worker server", :aggregate_failures do
      subject.launch

      expect(subject.config.instances("web_instances").keys).to eq %w[1 2 3 4]
      expect(subject.config.instances("worker_instances").keys).to eq %w[1 2]
    end

    it "carries the old slot's subnet, type and size onto the new one", :aggregate_failures do
      subject.launch

      web = subject.config.instances("web_instances")
      expect(web["3"].slice("subnet_id", "instance_type", "volume_size")).to eq(
        "subnet_id" => %("subnet-0aaa"),
        "instance_type" => %("t3.medium"),
        "volume_size" => "20"
      )
      expect(web["4"].slice("subnet_id", "instance_type", "volume_size")).to eq(
        "subnet_id" => %("subnet-0bbb"),
        "instance_type" => %("t3.large"),
        "volume_size" => "40"
      )
    end

    it "names each new host from the host it replaces", :aggregate_failures do
      subject.launch

      expect(subject.config.instances("web_instances")["3"]["hostname"]).to eq %("production-web3")
      expect(subject.config.instances("web_instances")["4"]["hostname"]).to eq %("production-web4")
      expect(subject.config.instances("worker_instances")["2"]["hostname"]).to eq %("production-worker2")
    end

    it "builds every new slot from the target ami", :aggregate_failures do
      subject.launch

      expect(subject.config.instances("web_instances")["3"]["ami"]).to eq %("ami-0new")
      expect(subject.config.instances("web_instances")["4"]["ami"]).to eq %("ami-0new")
      expect(subject.config.instances("worker_instances")["2"]["ami"]).to eq %("ami-0new")
    end

    it "leaves the new web servers out of the load balancer" do
      subject.launch

      expect(subject.config.list_argument("lb_instances")).to eq %w[1 2]
    end

    it "expects a create for every resource keyed by a new slot", :aggregate_failures do
      expected = nil
      allow(subject).to receive(:apply!) { |changes, **| expected = changes }

      subject.launch

      expect(expected).to eq new_slot_creates
      expect(expected.keys).not_to include(
        a_string_including("aws_lb_target_group_attachment"),
        a_string_including("aws_db_instance"),
        a_string_including("aws_lb.")
      )
    end

    it "records launching before terraform creates anything" do
      subject.launch

      expect(subject).to have_received(:apply!).with(anything, starting: "launching")
    end

    it "adds every new host to the upgrade group" do
      subject.launch

      expect(Subspace::Inventory.read("config/subspace/inventory.yml").groups.fetch("upgrade").host_list)
        .to eq %w[production-web3 production-web4 production-worker2]
    end

    context "when a previous upgrade was never finalized" do
      let(:lb_instances) { %w[1] }

      it "refuses before recording anything", :aggregate_failures do
        expect { subject.launch }.to raise_error SystemExit, /web slots that are not in lb_instances: 2/
        expect(reread_state).not_to have_key "web_slots"
      end
    end

    context "without worker servers" do
      let(:worker_tf) { "" }

      it "refuses before recording anything", :aggregate_failures do
        expect { subject.launch }.to raise_error SystemExit, /has no worker_instances/
        expect(reread_state).not_to have_key "web_slots"
      end
    end

    context "when a previous launch did not finish" do
      let(:web_tf) { old_web_tf + new_web_tf }
      let(:worker_tf) { old_worker_tf + new_worker_tf }
      let(:upgrade) { { "template" => "oxenwagen", "phase" => "launching" }.merge(recorded_slots) }

      it "finishes the slots it already picked", :aggregate_failures do
        subject.launch

        expect(subject.config.instances("web_instances").keys).to eq %w[1 2 3 4]
        expect(subject.config.instances("worker_instances").keys).to eq %w[1 2]
        expect(subject).to have_received(:apply!).with(new_slot_creates, starting: "launching")
      end

      it "re-checks without requiring a clean plan" do
        subject.launch

        expect(subject).to have_received(:check!).with(clean_plan: false)
      end
    end
  end

  describe "#provision" do
    let(:phase) { "launched" }

    let(:base_stage) do
      <<~RUBY
        set :branch, "main"
        server '100.64.0.1', user: 'deploy', roles: %w{web app} # production-web1
        server '100.64.0.2', user: 'deploy', roles: %w{web app} # production-web2
        server '100.64.0.5', user: 'deploy', roles: %w{app db} # production-worker1
      RUBY
    end

    let(:upgrade_stage) { File.read "config/deploy/production_upgrade.rb" }
    let(:upgrade_server_lines) { upgrade_stage.lines(chomp: true).grep(/\Aserver /) }

    before do
      Subspace::Upgrade::State.create("production", upgrade).save
      FileUtils.mkdir_p "config/deploy"
      File.write "config/deploy/production.rb", base_stage
      allow(Subspace::Commands::Bootstrap).to receive(:new)
      allow(subject).to receive(:provision!)
      allow(subject).to receive(:join_tailnet!)
    end

    it "masks cron on the new workers only", :aggregate_failures do
      subject.provision

      expect(subject).to have_received(:playbook)
        .with("upgrade_mask_cron", "production-worker2", upgrade_host: "production-worker2")
      expect(subject).not_to have_received(:playbook).with("upgrade_mask_cron", /web/, any_args)
    end

    it "writes the upgrade stage with only the new servers", :aggregate_failures do
      subject.provision

      expect(upgrade_stage).to include("'100.64.0.3'", "'100.64.0.4'", "'100.64.0.6'")
      expect(upgrade_stage).not_to include("'100.64.0.1'", "'100.64.0.2'", "'100.64.0.5'")
      expect(upgrade_stage).to include %(set :branch, "main")
    end

    it "gives the new worker the db role and the new web servers the web role" do
      subject.provision

      expect(upgrade_server_lines).to eq [
        "server '100.64.0.3', user: 'deploy', roles: %w{web app} # production-web3",
        "server '100.64.0.4', user: 'deploy', roles: %w{web app} # production-web4",
        "server '100.64.0.6', user: 'deploy', roles: %w{app db} # production-worker2",
      ]
    end

    context "when the old server line has extra options" do
      let(:base_stage) do
        <<~RUBY
          set :branch, "main"
          server '100.64.0.1', user: 'deploy', roles: %w{web app}, ssh_options: { forward_agent: true } # production-web1
          server '100.64.0.2', user: 'deploy', roles: %w{web app} # production-web2
          server '100.64.0.5', user: 'deploy', roles: %w{app db} # production-worker1
        RUBY
      end

      it "carries them onto every new line", :aggregate_failures do
        subject.provision

        expect(upgrade_server_lines).to eq [
          "server '100.64.0.3', user: 'deploy', roles: %w{web app}, ssh_options: { forward_agent: true } # production-web3",
          "server '100.64.0.4', user: 'deploy', roles: %w{web app}, ssh_options: { forward_agent: true } # production-web4",
          "server '100.64.0.6', user: 'deploy', roles: %w{app db}, ssh_options: { forward_agent: true } # production-worker2",
        ]
        expect(subject).to have_received(:say).with(a_string_matching(/Compare it with config\/deploy\/production.rb line by line/))
        expect(subject).to have_received(:say).with(a_string_matching(/carrying over `ssh_options: \{ forward_agent: true \}`/))
      end
    end

    it "advances to prepared" do
      subject.provision

      expect(reread_phase).to eq "prepared"
    end
  end

  describe "#cutover" do
    let(:attach_changes) do
      {
        %(module.oxenwagen.aws_lb_target_group_attachment.web["3"]) => ["create"],
        %(module.oxenwagen.aws_lb_target_group_attachment.web["4"]) => ["create"],
      }
    end

    let(:detach_changes) do
      {
        %(module.oxenwagen.aws_lb_target_group_attachment.web["1"]) => ["delete"],
        %(module.oxenwagen.aws_lb_target_group_attachment.web["2"]) => ["delete"],
      }
    end

    let(:upgrade_stage) { stage_header + new_server_lines + "# moved across by hand\n" }
    let(:events) { [] }

    before do
      Subspace::Upgrade::State.create("production", upgrade).save
      FileUtils.mkdir_p "config/deploy"
      File.write "config/deploy/production.rb", <<~RUBY
        server '100.64.0.1', user: 'deploy', roles: %w{web app} # production-web1
        server '100.64.0.2', user: 'deploy', roles: %w{web app} # production-web2
        server '100.64.0.5', user: 'deploy', roles: %w{app db} # production-worker1
      RUBY
      File.write "config/deploy/production_upgrade.rb", upgrade_stage
      allow(subject).to receive(:apply!)
    end

    it "hands the workers over before touching the load balancer", :aggregate_failures do
      subject.cutover

      expect(subject).to have_received(:playbook)
        .with("upgrade_quiesce", "production-worker1", upgrade_host: "production-worker1").ordered
      expect(subject).to have_received(:playbook)
        .with("upgrade_unmask_cron", "production-worker2", upgrade_host: "production-worker2").ordered
      expect(subject).to have_received(:apply!).with(attach_changes).ordered
    end

    it "records cutting_over before the handover" do
      phase_at_quiesce = nil
      allow(subject).to receive(:playbook) do |name, *|
        phase_at_quiesce = reread_phase if name == "upgrade_quiesce"
        true
      end

      subject.cutover

      expect(phase_at_quiesce).to eq "cutting_over"
    end

    it "attaches the new web slots and only then removes the old ones", :aggregate_failures do
      allow(subject).to receive(:apply!) { |changes| events << [changes, subject.config.list_argument("lb_instances")] }

      subject.cutover

      expect(events).to eq [[attach_changes, %w[1 2 3 4]], [detach_changes, %w[3 4]]]
      expect(subject.config.list_argument("lb_instances")).to eq %w[3 4]
    end

    it "waits for AWS to call the new targets healthy before detaching" do
      replies = [{ "i-0web3" => "initial", "i-0web4" => "initial" }, target_health, target_health]
      allow(Subspace::Elb).to receive(:target_health) do
        events << :target_health
        replies.shift
      end
      allow(subject).to receive(:apply!) { |changes| events << changes }

      subject.cutover

      expect(events).to eq [attach_changes, :target_health, :target_health, detach_changes, :target_health]
    end

    it "refuses to detach the old servers when the new ones never become healthy", :aggregate_failures do
      allow(Subspace::Elb).to receive(:target_health).and_return("i-0web3" => "unhealthy", "i-0web4" => "unhealthy")

      expect { subject.cutover }.to raise_error SystemExit, /has not reported the new web servers healthy/
      expect(subject.config.list_argument("lb_instances")).to eq %w[1 2 3 4]
      expect(subject).to have_received(:apply!).once
    end

    it "aborts when one of several new servers is unhealthy" do
      allow(Subspace::Elb).to receive(:target_health).and_return("i-0web3" => "healthy", "i-0web4" => "initial")

      expect { subject.cutover }.to raise_error SystemExit, /i-0web4 initial/
    end

    it "treats a target AWS has dropped as drained", :aggregate_failures do
      expect { subject.cutover }.not_to raise_error
      expect(Subspace::Elb).to have_received(:target_health).twice
      expect(subject).not_to have_received :sleep
    end

    it "sends the operator back to --cutover when draining times out", :aggregate_failures do
      allow(Subspace::Elb).to receive(:target_health)
        .and_return("i-0web1" => "draining", "i-0web2" => "draining", "i-0web3" => "healthy", "i-0web4" => "healthy")

      expect { subject.cutover }.to raise_error SystemExit, /re-run `subspace upgrade production --cutover`/
      expect(reread_phase).to eq "cutting_over"
    end

    it "aborts when the web servers are on different releases", :aggregate_failures do
      allow(subject).to receive(:playbook).with("upgrade_release", any_args).and_return false

      expect { subject.cutover }.to raise_error SystemExit, /same release/
      expect(subject).not_to have_received :apply!
    end

    it "verifies the new workers with the worker playbook, not the web one", :aggregate_failures do
      subject.cutover

      expect(subject).to have_received(:playbook)
        .with("upgrade_verify_worker", "production-worker2", upgrade_host: "production-worker2")
      expect(subject).not_to have_received(:playbook).with("upgrade_verify", "production-worker2", any_args)
    end

    it "copies the reviewed upgrade stage over the base stage", :aggregate_failures do
      subject.cutover

      expect(File.read("config/deploy/production.rb")).to eq new_server_lines + "# moved across by hand\n"
      expect(File).not_to exist "config/deploy/production_upgrade.rb"
    end

    it "advances to cutover" do
      subject.cutover

      expect(reread_phase).to eq "cutover"
    end

    it "records each apply as it lands", :aggregate_failures do
      subject.cutover

      expect(reread_state["lb_attached"]).to eq true
      expect(reread_state["lb_detached"]).to eq true
    end

    it "does not record an attach whose apply failed" do
      allow(subject).to receive(:apply!) { abort "terraform apply failed" }

      expect { subject.cutover }.to raise_error SystemExit
      expect(reread_state).not_to have_key "lb_attached"
    end

    context "when a previous attach apply failed" do
      let(:phase) { "cutting_over" }
      let(:lb_instances) { %w[1 2 3 4] }

      it "re-applies the attach and records it", :aggregate_failures do
        subject.cutover

        expect(subject).to have_received(:apply!).with(attach_changes).ordered
        expect(subject).to have_received(:apply!).with(detach_changes).ordered
        expect(reread_state["lb_attached"]).to eq true
      end

      it "re-checks without requiring a clean plan" do
        subject.cutover

        expect(subject).to have_received(:check!).with(clean_plan: false)
      end
    end

    context "when a previous cutover already attached the new servers" do
      let(:phase) { "cutting_over" }
      let(:lb_instances) { %w[1 2 3 4] }
      let(:lb_record) { { "lb_attached" => true } }

      it "does not attach them twice", :aggregate_failures do
        subject.cutover

        expect(subject).to have_received(:apply!).once
        expect(subject).to have_received(:apply!).with(detach_changes)
      end
    end

    context "when a previous cutover already detached the old servers" do
      let(:phase) { "cutting_over" }
      let(:lb_instances) { %w[3 4] }
      let(:lb_record) { { "lb_attached" => true, "lb_detached" => true } }

      it "applies nothing and finishes", :aggregate_failures do
        subject.cutover

        expect(subject).not_to have_received :apply!
        expect(reread_phase).to eq "cutover"
      end
    end

    context "when upgrade.yml and main.tf disagree about the attach" do
      let(:phase) { "cutting_over" }
      let(:lb_record) { { "lb_attached" => true } }

      it "refuses rather than guessing", :aggregate_failures do
        expect { subject.cutover }.to raise_error SystemExit,
          a_string_matching(/lb_attached is true, but lb_instances/).and(a_string_matching(/has not happened for slots 3, 4/))
        expect(subject).not_to have_received :apply!
      end
    end

    context "when a previous detach apply failed" do
      let(:phase) { "cutting_over" }
      let(:lb_instances) { %w[3 4] }
      let(:lb_record) { { "lb_attached" => true } }

      it "re-applies the detach and records it", :aggregate_failures do
        subject.cutover

        expect(subject).to have_received(:apply!).once
        expect(subject).to have_received(:apply!).with(detach_changes)
        expect(reread_state["lb_detached"]).to eq true
      end
    end

    context "when upgrade.yml records a detach main.tf does not show" do
      let(:phase) { "cutting_over" }
      let(:lb_instances) { %w[1 2 3 4] }
      let(:lb_record) { { "lb_attached" => true, "lb_detached" => true } }

      it "refuses rather than guessing", :aggregate_failures do
        expect { subject.cutover }.to raise_error SystemExit, /lb_detached is true, but lb_instances/
        expect(subject).not_to have_received :apply!
      end
    end
  end

  describe "#finalize" do
    let(:phase) { "cutover" }
    let(:lb_instances) { %w[3 4] }

    let(:old_slot_deletes) do
      {
        %(module.oxenwagen.aws_instance.web["1"]) => ["delete"],
        %(module.oxenwagen.aws_instance.web["2"]) => ["delete"],
        %(module.oxenwagen.aws_eip.web["1"]) => ["delete"],
        %(module.oxenwagen.aws_eip.web["2"]) => ["delete"],
        %(module.oxenwagen.aws_eip_association.eip_assoc["1"]) => ["delete"],
        %(module.oxenwagen.aws_eip_association.eip_assoc["2"]) => ["delete"],
        %(module.oxenwagen.aws_route53_record.web["1"]) => ["delete"],
        %(module.oxenwagen.aws_route53_record.web["2"]) => ["delete"],
        %(module.oxenwagen.aws_instance.worker["1"]) => ["delete"],
        %(module.oxenwagen.aws_eip.worker["1"]) => ["delete"],
        %(module.oxenwagen.aws_eip_association.worker_eip_assoc["1"]) => ["delete"],
        %(module.oxenwagen.aws_route53_record.worker["1"]) => ["delete"],
      }
    end

    before do
      Subspace::Upgrade::State.create("production", upgrade).save
      allow(subject).to receive(:ask).and_return "production"
      allow(subject).to receive(:apply!)
      allow(subject).to receive(:remove_host!)
      allow(subject).to receive(:remove_from_group!)
    end

    it "removes every old slot from both maps", :aggregate_failures do
      subject.finalize

      expect(subject.config.instances("web_instances").keys).to eq %w[3 4]
      expect(subject.config.instances("worker_instances").keys).to eq %w[2]
    end

    it "expects a delete for every resource keyed by an old slot", :aggregate_failures do
      expected = nil
      allow(subject).to receive(:apply!) { |changes, **| expected = changes }

      subject.finalize

      expect(expected).to eq old_slot_deletes
      expect(expected.keys).not_to include(
        a_string_including("aws_db_instance"),
        a_string_including("aws_lb."),
        a_string_including("aws_elasticache_cluster"),
        a_string_including("aws_s3_bucket")
      )
    end

    it "removes the old hosts and takes the new ones out of the upgrade group", :aggregate_failures do
      subject.finalize

      expect(subject).to have_received(:remove_host!).exactly(3).times
      expect(subject).to have_received(:remove_host!).with("production-web1")
      expect(subject).to have_received(:remove_host!).with("production-web2")
      expect(subject).to have_received(:remove_host!).with("production-worker1")
      expect(subject).to have_received(:remove_from_group!).exactly(3).times
      expect(subject).to have_received(:remove_from_group!).with("production-web3", "upgrade")
      expect(subject).to have_received(:remove_from_group!).with("production-web4", "upgrade")
      expect(subject).to have_received(:remove_from_group!).with("production-worker2", "upgrade")
    end

    context "when a previous finalize's destroy failed" do
      let(:phase) { "finalizing" }
      let(:web_tf) { new_web_tf }
      let(:worker_tf) { new_worker_tf }

      it "finishes the destroy", :aggregate_failures do
        expect { subject.finalize }.not_to raise_error
        expect(subject).to have_received(:apply!).with(old_slot_deletes, starting: "finalizing")
        expect(subject).to have_received(:check!).with(clean_plan: false)
        expect(reread_phase).to eq "finalized"
      end
    end

    context "when the upgrade has not cut over" do
      let(:phase) { "prepared" }

      it "will not finalize before cutover" do
        expect { subject.finalize }.to raise_error SystemExit, /requires cutover/
      end
    end
  end

  describe "#abort_upgrade" do
    let(:target_health) { { "i-0web1" => "healthy", "i-0web2" => "healthy" } }
    let(:events) { [] }

    let(:detach_new_changes) do
      {
        %(module.oxenwagen.aws_lb_target_group_attachment.web["3"]) => ["delete"],
        %(module.oxenwagen.aws_lb_target_group_attachment.web["4"]) => ["delete"],
      }
    end

    let(:new_slot_deletes) do
      {
        %(module.oxenwagen.aws_instance.web["3"]) => ["delete"],
        %(module.oxenwagen.aws_instance.web["4"]) => ["delete"],
        %(module.oxenwagen.aws_eip.web["3"]) => ["delete"],
        %(module.oxenwagen.aws_eip.web["4"]) => ["delete"],
        %(module.oxenwagen.aws_eip_association.eip_assoc["3"]) => ["delete"],
        %(module.oxenwagen.aws_eip_association.eip_assoc["4"]) => ["delete"],
        %(module.oxenwagen.aws_route53_record.web["3"]) => ["delete"],
        %(module.oxenwagen.aws_route53_record.web["4"]) => ["delete"],
        %(module.oxenwagen.aws_instance.worker["2"]) => ["delete"],
        %(module.oxenwagen.aws_eip.worker["2"]) => ["delete"],
        %(module.oxenwagen.aws_eip_association.worker_eip_assoc["2"]) => ["delete"],
        %(module.oxenwagen.aws_route53_record.worker["2"]) => ["delete"],
      }
    end

    before do
      Subspace::Upgrade::State.create("production", upgrade).save
      FileUtils.mkdir_p "config/deploy"
      File.write "config/deploy/production_upgrade.rb", stage_header + new_server_lines
      allow(subject).to receive(:ask).and_return "production"
      allow(subject).to receive(:apply!)
      allow(subject).to receive(:remove_host!)
    end

    it "destroys only the new slots", :aggregate_failures do
      subject.abort_upgrade

      expect(subject).to have_received(:apply!).with(new_slot_deletes, starting: "aborting")
      expect(subject.config.instances("web_instances").keys).to eq %w[1 2]
      expect(subject.config.instances("worker_instances").keys).to eq %w[1]
    end

    it "checks without requiring a clean plan" do
      subject.abort_upgrade

      expect(subject).to have_received(:check!).with(clean_plan: false)
    end

    context "when a cutover did not finish" do
      let(:phase) { "cutting_over" }

      it "starts the old workers back up" do
        subject.abort_upgrade

        expect(subject).to have_received(:playbook)
          .with("upgrade_unquiesce", "production-worker1", upgrade_host: "production-worker1")
      end

      it "masks cron on the new workers before starting the old ones", :aggregate_failures do
        subject.abort_upgrade

        expect(subject).to have_received(:playbook)
          .with("upgrade_mask_cron", "production-worker2", upgrade_host: "production-worker2").ordered
        expect(subject).to have_received(:playbook)
          .with("upgrade_unquiesce", "production-worker1", upgrade_host: "production-worker1").ordered
      end

      context "after it attached the new servers" do
        let(:lb_instances) { %w[1 2 3 4] }
        let(:lb_record) { { "lb_attached" => true } }

        it "detaches and drains the new servers first when a cutover had attached them", :aggregate_failures do
          allow(Subspace::Elb).to receive(:target_health) do
            events << :target_health
            target_health
          end
          allow(subject).to receive(:apply!) { |changes, **| events << changes }

          subject.abort_upgrade

          expect(events).to eq [detach_new_changes, :target_health, new_slot_deletes]
          expect(subject.config.list_argument("lb_instances")).to eq %w[1 2]
        end
      end

      context "when upgrade.yml does not record the attach" do
        let(:lb_instances) { %w[1 2 3 4] }

        it "recovers from a disagreement instead of refusing" do
          subject.abort_upgrade

          expect(subject).to have_received(:apply!).with(detach_new_changes)
        end
      end

      context "when a cutover already detached the old servers" do
        let(:lb_instances) { %w[3 4] }
        let(:lb_record) { { "lb_attached" => true, "lb_detached" => true } }

        it "refuses and points at --cutover", :aggregate_failures do
          expect { subject.abort_upgrade }.to raise_error SystemExit, /There is no --abort from here/
          expect(subject).not_to have_received :apply!
          expect(subject.config.list_argument("lb_instances")).to eq %w[3 4]
        end
      end
    end

    context "when the new servers were never attached" do
      let(:phase) { "launched" }

      it "does nothing to the load balancer when the new servers were never attached", :aggregate_failures do
        expected = nil
        allow(subject).to receive(:apply!) { |changes, **| expected = changes }

        subject.abort_upgrade

        expect(subject).to have_received(:apply!).once
        expect(expected.keys).not_to include a_string_including("aws_lb_target_group_attachment")
      end
    end

    context "when the upgrade has cut over" do
      let(:phase) { "cutover" }

      it "refuses after cutover" do
        expect { subject.abort_upgrade }.to raise_error SystemExit, /requires/
      end
    end

    context "when a previous abort's destroy failed" do
      let(:phase) { "aborting" }
      let(:web_tf) { old_web_tf }
      let(:worker_tf) { old_worker_tf }

      it "finishes the destroy", :aggregate_failures do
        expect { subject.abort_upgrade }.not_to raise_error
        expect(subject).to have_received(:apply!).with(new_slot_deletes, starting: "aborting")
      end

      it "does not touch the removed workers", :aggregate_failures do
        subject.abort_upgrade

        expect(subject).not_to have_received(:playbook).with("upgrade_mask_cron", any_args)
        expect(subject).not_to have_received(:playbook).with("upgrade_unquiesce", any_args)
      end
    end

    it "removes the new hosts and the upgrade stage", :aggregate_failures do
      subject.abort_upgrade

      expect(subject).to have_received(:remove_host!).exactly(3).times
      expect(subject).to have_received(:remove_host!).with("production-web3")
      expect(subject).to have_received(:remove_host!).with("production-web4")
      expect(subject).to have_received(:remove_host!).with("production-worker2")
      expect(File.exist?("config/deploy/production_upgrade.rb")).to eq false
    end

    %w[launching prepared].each do |before_cutover|
      context "when the abort starts before a cutover (#{before_cutover})" do
        let(:phase) { before_cutover }

        it "leaves the workers alone", :aggregate_failures do
          subject.abort_upgrade

          expect(subject).not_to have_received(:playbook).with("upgrade_mask_cron", any_args)
          expect(subject).not_to have_received(:playbook).with("upgrade_unquiesce", any_args)
        end
      end
    end
  end

  describe "#copy_db" do
    it "says the database is shared" do
      expect { subject.copy_db }.to raise_error SystemExit, /RDS, which both the old and new servers share/
    end
  end

  describe "#close_instance_ssh" do
    it "says there is nothing to close" do
      expect { subject.close_instance_ssh }.to raise_error SystemExit, /internal security group/
    end
  end

  describe "#check" do
    let(:web_tf) { old_web_tf }
    let(:worker_tf) { old_worker_tf }

    before do
      FileUtils.mkdir_p "config/subspace/terraform/production/modules/oxenwagen"
      File.write "config/subspace/terraform/production/modules/oxenwagen/module.yml",
        YAML.dump("template" => "oxenwagen", "version" => Subspace::VERSION)
      allow(subject).to receive(:check_remote_storage!)
      allow(subject).to receive(:check_tailscale!)
    end

    context "without worker servers" do
      let(:worker_tf) { "" }

      it "refuses" do
        expect { subject.check }.to raise_error SystemExit, /has no worker_instances/
      end
    end

    it "refuses when the region has no room for the new elastic IPs" do
      allow(Subspace::Ec2).to receive(:elastic_ip_headroom).and_return 2

      expect { subject.check }.to raise_error SystemExit, /needs 3 more elastic IPs and this region has room for 2/
    end

    it "passes when the region has exactly enough room" do
      allow(Subspace::Ec2).to receive(:elastic_ip_headroom).and_return 3

      expect { subject.check }.not_to raise_error
    end

    it "checks the elastic IP quota in the module's region" do
      subject.check

      expect(Subspace::Ec2).to have_received(:elastic_ip_headroom).with(hash_including(region: "us-west-2"))
    end

    context "when an upgrade is in progress" do
      before { Subspace::Upgrade::State.create("production", upgrade).save }

      it "does not check the elastic IP quota" do
        subject.check

        expect(Subspace::Ec2).not_to have_received :elastic_ip_headroom
      end
    end
  end

  describe "#revendor" do
    context "when main.tf is still on the count-based variables" do
      let(:main_tf) { count_based_main_tf }

      it "refuses until the slot maps are pasted", :aggregate_failures do
        expect { subject.revendor }.to raise_error SystemExit,
          /Run `subspace upgrade production --migrate` and paste what it prints before re-vendoring/
        expect(File.read("config/subspace/terraform/production/main.tf")).to eq main_tf
      end
    end

    context "when main.tf has been converted" do
      before do
        allow(subject).to receive(:check_not_cloned!)
        allow(subject).to receive(:locally_modified_files).and_return []
        allow(subject).to receive(:update_gitignore!)
        allow(Subspace::Upgrade::ModuleManifest).to receive(:vendor)
      end

      it "re-vendors" do
        subject.revendor

        expect(Subspace::Upgrade::ModuleManifest).to have_received(:vendor)
          .with("oxenwagen", "config/subspace/terraform/production/modules/oxenwagen")
      end
    end
  end

  describe "#migrate" do
    let(:first_web_hostname) { "production-web1" }
    let(:resources) do
      [
        {
          "address" => "module.oxenwagen.aws_instance.web[0]", "type" => "aws_instance", "name" => "web", "index" => 0,
          "values" => {
            "tags" => { "Name" => first_web_hostname },
            "ami" => "ami-0abc", "instance_type" => "t3.small", "subnet_id" => "subnet-0a",
            "root_block_device" => [{ "volume_size" => 16 }],
          },
        },
        {
          "address" => "module.oxenwagen.aws_instance.web[1]", "type" => "aws_instance", "name" => "web", "index" => 1,
          "values" => {
            "tags" => { "Name" => "production-web2" },
            "ami" => "ami-0abc", "instance_type" => "t3.small", "subnet_id" => "subnet-0b",
            "root_block_device" => [{ "volume_size" => 16 }],
          },
        },
        {
          "address" => "module.oxenwagen.aws_instance.worker[0]", "type" => "aws_instance", "name" => "worker", "index" => 0,
          "values" => {
            "tags" => { "Name" => "production-worker1" },
            "ami" => "ami-0abc", "instance_type" => "t3.medium", "subnet_id" => "subnet-0a",
            "root_block_device" => [{ "volume_size" => 100 }],
          },
        },
      ]
    end
    let(:state_list) do
      %w[
        module.oxenwagen.aws_db_instance.production
        module.oxenwagen.aws_eip.web[0]
        module.oxenwagen.aws_eip.web[1]
        module.oxenwagen.aws_eip.worker[0]
        module.oxenwagen.aws_eip_association.eip_assoc[0]
        module.oxenwagen.aws_eip_association.eip_assoc[1]
        module.oxenwagen.aws_eip_association.worker_eip_assoc[0]
        module.oxenwagen.aws_instance.web[0]
        module.oxenwagen.aws_instance.web[1]
        module.oxenwagen.aws_instance.worker[0]
        module.oxenwagen.aws_lb.production
        module.oxenwagen.aws_lb_target_group.production[0]
        module.oxenwagen.aws_lb_target_group_attachment.web[0]
        module.oxenwagen.aws_lb_target_group_attachment.web[1]
      ]
    end
    let(:said) { [] }
    let(:output) { said.join "\n" }
    let(:expected_migration) do
      <<~TEXT.chomp
        config/subspace/terraform/production/main.tf is still on oxenwagen's count-based variables.  Replace
        instance_ami, web_instance_count, web_instance_type, web_volume_size and their
        worker_ equivalents in the module block with:

          web_instances = {
            "1" = {
              hostname      = "production-web1"
              ami           = "ami-0abc"
              instance_type = "t3.small"
              volume_size   = 16
              subnet_id     = "subnet-0a"
            }
            "2" = {
              hostname      = "production-web2"
              ami           = "ami-0abc"
              instance_type = "t3.small"
              volume_size   = 16
              subnet_id     = "subnet-0b"
            }
          }
          lb_instances = ["1", "2"]

          worker_instances = {
            "1" = {
              hostname      = "production-worker1"
              ami           = "ami-0abc"
              instance_type = "t3.medium"
              volume_size   = 100
              subnet_id     = "subnet-0a"
            }
          }

        Re-export the module's outputs at the root of the same file, replacing the
        single `output "inventory" { value = module.oxenwagen }`:

        output "inventory" { value = module.oxenwagen.inventory }
        output "web_instances" { value = module.oxenwagen.web_instances }
        output "worker_instances" { value = module.oxenwagen.worker_instances }
        output "lb_instances" { value = module.oxenwagen.lb_instances }
        output "lb_target_group_arn" { value = module.oxenwagen.lb_target_group_arn }

        Add a moved block for every resource still keyed by count:

        moved {
          from = module.oxenwagen.aws_eip.web[0]
          to   = module.oxenwagen.aws_eip.web["1"]
        }
        moved {
          from = module.oxenwagen.aws_eip.web[1]
          to   = module.oxenwagen.aws_eip.web["2"]
        }
        moved {
          from = module.oxenwagen.aws_eip.worker[0]
          to   = module.oxenwagen.aws_eip.worker["1"]
        }
        moved {
          from = module.oxenwagen.aws_eip_association.eip_assoc[0]
          to   = module.oxenwagen.aws_eip_association.eip_assoc["1"]
        }
        moved {
          from = module.oxenwagen.aws_eip_association.eip_assoc[1]
          to   = module.oxenwagen.aws_eip_association.eip_assoc["2"]
        }
        moved {
          from = module.oxenwagen.aws_eip_association.worker_eip_assoc[0]
          to   = module.oxenwagen.aws_eip_association.worker_eip_assoc["1"]
        }
        moved {
          from = module.oxenwagen.aws_instance.web[0]
          to   = module.oxenwagen.aws_instance.web["1"]
        }
        moved {
          from = module.oxenwagen.aws_instance.web[1]
          to   = module.oxenwagen.aws_instance.web["2"]
        }
        moved {
          from = module.oxenwagen.aws_instance.worker[0]
          to   = module.oxenwagen.aws_instance.worker["1"]
        }
        moved {
          from = module.oxenwagen.aws_lb_target_group_attachment.web[0]
          to   = module.oxenwagen.aws_lb_target_group_attachment.web["1"]
        }
        moved {
          from = module.oxenwagen.aws_lb_target_group_attachment.web[1]
          to   = module.oxenwagen.aws_lb_target_group_attachment.web["2"]
        }

        Then `subspace upgrade production --revendor`, `terraform init`, and
        `subspace upgrade production --migrate` again to apply them.
      TEXT
    end

    before do
      allow(subject).to receive(:say) { |message| said << message }
      allow(subject).to receive(:check_module_version!)
      allow(subject).to receive(:check_module_variables!)
      allow(subject).to receive(:apply!)
      allow(terraform).to receive(:resources).and_return resources
      allow(terraform).to receive(:state_list).and_return state_list
    end

    context "when main.tf is still on the count-based variables" do
      let(:main_tf) { count_based_main_tf }

      it "prints the whole migration" do
        subject.migrate

        expect(output).to eq expected_migration
      end

      it "prints a slot map built from live state", :aggregate_failures do
        subject.migrate

        expect(output).to include 'hostname      = "production-web1"'
        expect(output).to include 'subnet_id     = "subnet-0a"'
        expect(output).to include "volume_size   = 16"
      end

      context "with a host renamed by hand" do
        let(:first_web_hostname) { "production-frontend1" }

        it "takes each hostname from the live Name tag", :aggregate_failures do
          subject.migrate

          expect(output).to include 'hostname      = "production-frontend1"'
          expect(output).not_to include '"production-web1"'
        end
      end

      it "keys slots from one, not zero", :aggregate_failures do
        subject.migrate

        expect(output).to match(/"1" = \{\s+hostname\s+= "production-web1"/)
        expect(output).to match(/"2" = \{\s+hostname\s+= "production-web2"/)
        expect(output).not_to include '"0" = {'
      end

      it "attaches every web slot to the load balancer" do
        subject.migrate

        expect(output).to include 'lb_instances = ["1", "2"]'
      end

      it "prints a root output for every required output", :aggregate_failures do
        subject.migrate

        described_class::REQUIRED_ROOT_OUTPUTS.each do |name|
          expect(output).to include %(output "#{name}" { value = module.oxenwagen.#{name} })
        end
      end

      it "prints a moved block for every count-keyed address" do
        subject.migrate

        expect(output.scan(/^moved \{\n.*?\n\}/m)).to eq [
          %(moved {\n  from = module.oxenwagen.aws_eip.web[0]\n  to   = module.oxenwagen.aws_eip.web["1"]\n}),
          %(moved {\n  from = module.oxenwagen.aws_eip.web[1]\n  to   = module.oxenwagen.aws_eip.web["2"]\n}),
          %(moved {\n  from = module.oxenwagen.aws_eip.worker[0]\n  to   = module.oxenwagen.aws_eip.worker["1"]\n}),
          %(moved {\n  from = module.oxenwagen.aws_eip_association.eip_assoc[0]\n  to   = module.oxenwagen.aws_eip_association.eip_assoc["1"]\n}),
          %(moved {\n  from = module.oxenwagen.aws_eip_association.eip_assoc[1]\n  to   = module.oxenwagen.aws_eip_association.eip_assoc["2"]\n}),
          %(moved {\n  from = module.oxenwagen.aws_eip_association.worker_eip_assoc[0]\n  to   = module.oxenwagen.aws_eip_association.worker_eip_assoc["1"]\n}),
          %(moved {\n  from = module.oxenwagen.aws_instance.web[0]\n  to   = module.oxenwagen.aws_instance.web["1"]\n}),
          %(moved {\n  from = module.oxenwagen.aws_instance.web[1]\n  to   = module.oxenwagen.aws_instance.web["2"]\n}),
          %(moved {\n  from = module.oxenwagen.aws_instance.worker[0]\n  to   = module.oxenwagen.aws_instance.worker["1"]\n}),
          %(moved {\n  from = module.oxenwagen.aws_lb_target_group_attachment.web[0]\n  to   = module.oxenwagen.aws_lb_target_group_attachment.web["1"]\n}),
          %(moved {\n  from = module.oxenwagen.aws_lb_target_group_attachment.web[1]\n  to   = module.oxenwagen.aws_lb_target_group_attachment.web["2"]\n}),
        ]
      end

      it "applies nothing" do
        subject.migrate

        expect(subject).not_to have_received :apply!
      end

      it "reads state without checking the vendored module", :aggregate_failures do
        subject.migrate

        expect(subject).not_to have_received :check_module_version!
        expect(subject).not_to have_received :check_module_variables!
      end

      it "tells the operator to re-vendor before applying" do
        subject.migrate

        expect(output).to include "Then `subspace upgrade production --revendor`, `terraform init`, and"
      end
    end

    context "with web_instances pasted but no lb_instances" do
      let(:main_tf) do
        <<~HCL
          module oxenwagen {
            source = "github.com/tenforwardconsulting/terraform-subspace-oxenwagen?ref=v2.4.1"

            web_instances = {
          #{old_web_tf}
            }
            worker_instance_type = "t3.medium"
            worker_instance_count = 1
            worker_volume_size = 100
          }

          output "inventory" {
            value = module.oxenwagen
          }
        HCL
      end

      it "stays on stage one", :aggregate_failures do
        subject.migrate

        expect(output).to eq expected_migration
        expect(subject).not_to have_received :apply!
      end
    end

    context "when main.tf has been converted" do
      let(:web_tf) { old_web_tf }
      let(:worker_tf) { old_worker_tf }

      it "applies with nothing allowed to change" do
        subject.migrate

        expect(subject).to have_received(:apply!).with({})
      end

      it "checks the vendored module before applying", :aggregate_failures do
        subject.migrate

        expect(subject).to have_received :check_module_version!
        expect(subject).to have_received :check_module_variables!
      end

      context "without the lb_target_group_arn root output" do
        before do
          path = "config/subspace/terraform/production/main.tf"
          File.write path, File.read(path).sub(/^output "lb_target_group_arn" \{\n.*\n\}\n/, "")
        end

        it "checks the root outputs before applying", :aggregate_failures do
          expect { subject.migrate }.to raise_error SystemExit, /does not re-export lb_target_group_arn/
          expect(subject).not_to have_received :apply!
        end
      end

      it "tells the operator to delete the moved blocks" do
        subject.migrate

        expect(output).to include "Delete the moved blocks from config/subspace/terraform/production/main.tf"
      end

      context "when nothing is keyed by count" do
        let(:state_list) do
          %w[
            module.oxenwagen.aws_instance.web["1"]
            module.oxenwagen.aws_instance.web["2"]
            module.oxenwagen.aws_instance.worker["1"]
            module.oxenwagen.aws_lb_target_group.production[0]
          ]
        end

        it "says it looks migrated", :aggregate_failures do
          expect { subject.migrate }.to raise_error SystemExit, /looks migrated already/
          expect(subject).not_to have_received :apply!
        end
      end
    end
  end

  describe "#migration_instructions" do
    let(:instructions) { subject.send(:migration_instructions) }

    it "puts --migrate before --revendor", :aggregate_failures do
      expect(instructions.index("--migrate")).to be < instructions.index("--revendor")
      expect(instructions).to include "Delete the moved blocks"
    end
  end

  describe "#slot_summary" do
    before { Subspace::Upgrade::State.create("production", upgrade).save }

    it "lists every web and worker pair" do
      expect(subject.send(:slot_summary)).to eq [
        "Web     1 (production-web1) => 3 (production-web3)",
        "Web     2 (production-web2) => 4 (production-web4)",
        "Worker  1 (production-worker1) => 2 (production-worker2)",
      ]
    end
  end
end
