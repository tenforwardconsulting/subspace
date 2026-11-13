require 'spec_helper'
require 'subspace/commands/inventory'

describe Subspace::Commands::Inventory do
  describe ".server_lines" do
    context "with web hosts" do
      let(:hosts) do
        [
          Subspace::Inventory::Host.new("production-web1", vars: { "ansible_host" => "10.0.0.1", "hostname" => "production-web1" }, group_list: %w[production production_web])
        ]
      end

      it "gives web hosts the web and app roles" do
        lines = described_class.server_lines(hosts)
        expect(lines).to eq([
          "server '10.0.0.1', user: 'deploy', roles: %w{web app} # production-web1"
        ])
      end
    end

    context "with multiple worker hosts" do
      let(:hosts) do
        [
          Subspace::Inventory::Host.new("production-worker1", vars: { "ansible_host" => "10.0.0.2", "hostname" => "production-worker1" }, group_list: %w[production production_worker]),
          Subspace::Inventory::Host.new("production-worker2", vars: { "ansible_host" => "10.0.0.3", "hostname" => "production-worker2" }, group_list: %w[production production_worker])
        ]
      end

      it "gives only the first worker the db role", :aggregate_failures do
        lines = described_class.server_lines(hosts)
        expect(lines[0]).to eq("server '10.0.0.2', user: 'deploy', roles: %w{app db} # production-worker1")
        expect(lines[1]).to eq("server '10.0.0.3', user: 'deploy', roles: %w{app} # production-worker2")
      end
    end

    context "with a workhorse host" do
      let(:hosts) do
        [
          Subspace::Inventory::Host.new("production-app1", vars: { "ansible_host" => "10.0.0.1", "hostname" => "production-app1" }, group_list: %w[production production_web production_worker])
        ]
      end

      it "lists each role once for a host that is both web and worker" do
        lines = described_class.server_lines(hosts)
        expect(lines).to eq([
          "server '10.0.0.1', user: 'deploy', roles: %w{web app db} # production-app1"
        ])
      end
    end

    context "with multiple hosts" do
      let(:hosts) do
        [
          Subspace::Inventory::Host.new("production-web1", vars: { "ansible_host" => "10.0.0.1", "hostname" => "production-web1" }, group_list: %w[production production_web]),
          Subspace::Inventory::Host.new("production-web2", vars: { "ansible_host" => "10.0.0.2", "hostname" => "production-web2" }, group_list: %w[production production_web]),
          Subspace::Inventory::Host.new("production-worker1", vars: { "ansible_host" => "10.0.0.3", "hostname" => "production-worker1" }, group_list: %w[production production_worker]),
          Subspace::Inventory::Host.new("production-worker2", vars: { "ansible_host" => "10.0.0.4", "hostname" => "production-worker2" }, group_list: %w[production production_worker])
        ]
      end

      it "returns a line per host in the order given" do
        lines = described_class.server_lines(hosts)
        expect(lines.length).to eq(4)
        expect(lines).to eq([
          "server '10.0.0.1', user: 'deploy', roles: %w{web app} # production-web1",
          "server '10.0.0.2', user: 'deploy', roles: %w{web app} # production-web2",
          "server '10.0.0.3', user: 'deploy', roles: %w{app db} # production-worker1",
          "server '10.0.0.4', user: 'deploy', roles: %w{app} # production-worker2"
        ])
      end
    end
  end
end
