require 'spec_helper'
require 'subspace/inventory'

describe Subspace::Inventory do
  let(:inventory) { Subspace::Inventory.new}

  context "Producing YAML" do
    it 'can add a host' do
      host = Subspace::Inventory::Host.new("web1")
      host.vars = {var1: "a", var2: "b"}
      host.groups = []
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
      inventory.hosts["web1"] = Subspace::Inventory::Host.new("web1", groups: ["webservers"])
      inventory.hosts["web2"] = Subspace::Inventory::Host.new("web2", groups: ["webservers"])

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
      inventory.hosts["web1"] = Subspace::Inventory::Host.new("web1", groups: ["webservers"])
      inventory.hosts["web2"] = Subspace::Inventory::Host.new("web2", groups: ["webservers"])
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
      inventory.hosts["web1"] = Subspace::Inventory::Host.new("web1", groups: ["webservers"])
      inventory.hosts["web2"] = Subspace::Inventory::Host.new("web2", groups: ["webservers"])
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
      EOS
    end
  end
end
