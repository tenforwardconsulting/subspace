require 'spec_helper'
require 'subspace/inventory'
require 'json'

describe Subspace::Inventory do
  let(:inventory) { Subspace::Inventory.new}

  context "Producing YAML" do
    it 'can add a host' do
      host = Subspace::Inventory::Host.new("web1")
      host.vars = {var1: "a", var2: "b"}
      inventory.hosts["web1"] = host
      expect(inventory.to_yml).to eq <<~EOS
        ---
        all:
          hosts:
            web1:
              var1: a
              var2: b
          children:
        EOS
    end

    it "can add a couple hosts to a group" do
      inventory.hosts["web1"] = Subspace::Inventory::Host.new("web1", group_list: ["webservers"])
      inventory.hosts["web2"] = Subspace::Inventory::Host.new("web2", group_list: ["webservers"])

      expect(inventory.to_yml).to eq <<~EOS
        ---
        all:
          hosts:
            web1:
            web2:
          children:
            webservers:
              hosts:
                web1:
                web2:
        EOS
    end

    # TODO I don't know if I want to do this, I think group_vars/ might be better
    it "can add group vars to a group with hosts in it" do
      inventory.hosts["web1"] = Subspace::Inventory::Host.new("web1", group_list: ["webservers"])
      inventory.hosts["web2"] = Subspace::Inventory::Host.new("web2", group_list: ["webservers"])
      inventory.group_vars["webservers"] = {
        var1: "a",
        var2: "b"
      }
      expect(inventory.to_yml).to eq <<~EOS
        ---
        all:
          hosts:
            web1:
            web2:
          children:
            webservers:
              hosts:
                web1:
                web2:
              vars:
                var1: a
                var2: b
        EOS
    end

    it "can add global vars too" do
      inventory.hosts["web1"] = Subspace::Inventory::Host.new("web1", group_list: ["webservers"])
      inventory.hosts["web2"] = Subspace::Inventory::Host.new("web2", group_list: ["webservers"])
      inventory.group_vars["webservers"] = {
        var1: "a",
        var2: "b"
      }
      inventory.global_vars["ruby_version"] = "3.0"
      inventory.global_vars["testing"] = true
      expect(inventory.to_yml).to eq <<~EOS
        ---
        all:
          hosts:
            web1:
            web2:
          children:
            webservers:
              hosts:
                web1:
                web2:
              vars:
                var1: a
                var2: b
          vars:
            ruby_version: '3.0'
            testing: true
        EOS
    end
  end

  context "Reading existing files" do
    let(:inventory) { Subspace::Inventory.read("spec/data/inventory_complex.yml") }

    it "knows all the hosts" do
      expect(inventory.hosts.keys).to match_array %w(mail.example.com one.example.com two.example.com three.example.com foo.example.com bar.example.com)
    end

    it "knows all the groups" do
      expect(inventory.groups.keys).to match_array %w(all webservers dbservers east west)
    end

    it "writes (most of) the yaml back after reading it" do
      expect(inventory.to_yml).to eq <<~EOS
      ---
      all:
        hosts:
          mail.example.com:
            var1: a
            var2: b
          foo.example.com:
          bar.example.com:
          one.example.com:
          two.example.com:
          three.example.com:
        children:
          webservers:
            hosts:
              foo.example.com:
              bar.example.com:
          east:
            hosts:
              foo.example.com:
              one.example.com:
              two.example.com:
          west:
            hosts:
              bar.example.com:
              three.example.com:
          dbservers:
            hosts:
              one.example.com:
              two.example.com:
              three.example.com:
        vars:
          global1: aaa
          global2: bbb
          arr_var:
          - this: is
            an: array
          - and: so
            is: this
      EOS
    end
  end

  context "Importing terraform output" do
    let(:tf_output) { JSON.parse(File.read("spec/data/tf_inventory_output.json"))["inventory"]["value"] }

    it "can read in hosts, ips, and groups into a blank inventory" do
      inventory.merge(tf_output)
      expect(inventory.hosts.keys).to eq ["staging-web1", "staging-web2", "staging-worker1"]
      expect(inventory.hosts["staging-web1"].vars).to eq({
        "ansible_host" => "10.1.1.1",
        "ansible_user" => "ubuntu",
        "hostname" => "staging-web1"
      })
      expect(inventory.hosts["staging-web2"].group_list).to eq ["staging", "staging_web"]
      expect(inventory.hosts["staging-worker1"].group_list).to eq ["staging", "staging_worker"]
    end

    it "can read in hosts and export yml from a blank inventory" do
      inventory.merge(tf_output)
      expect(inventory.to_yml).to eq <<~EOS
      ---
      all:
        hosts:
          staging-web1:
            ansible_host: 10.1.1.1
            ansible_user: ubuntu
            hostname: staging-web1
          staging-web2:
            ansible_host: 10.2.2.2
            ansible_user: ubuntu
            hostname: staging-web2
          staging-worker1:
            ansible_host: 10.3.3.3
            ansible_user: ubuntu
            hostname: staging-worker1
        children:
          staging:
            hosts:
              staging-web1:
              staging-web2:
              staging-worker1:
          staging_web:
            hosts:
              staging-web1:
              staging-web2:
          staging_worker:
            hosts:
              staging-worker1:
      EOS
    end

    context "With an existing inventory from a different group" do
      let(:inventory) { Subspace::Inventory.read("spec/data/inventory_prod.yml") }
      it "can merge in new hosts without disturbing existing ones" do
        inventory.merge(tf_output)
        expect(inventory.hosts.keys).to match_array ["staging-web1", "staging-web2", "staging-worker1", "prod-web1", "prod-web2", "prod-worker1"]
        expect(inventory.hosts["prod-web1"].group_list).to eq ["prod", "prod_web"]
      end
    end

    context "With an existing inventory from the same group" do
      let(:inventory) { Subspace::Inventory.read("spec/data/inventory_staging.yml") }
      it "can merge in new hosts replacing and removing old ones" do
        inventory.merge(tf_output)
        expect(inventory.hosts.keys).to match_array ["staging-web6", "staging-worker7", "staging-web1", "staging-web2", "staging-worker1"]
        expect(inventory.hosts["staging-web6"].vars["ansible_host"]).to eq "10.6.6.6"
      end
    end
  end
end
