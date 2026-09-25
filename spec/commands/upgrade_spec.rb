require 'spec_helper'
require 'subspace/commands/upgrade'

describe Subspace::Commands::Upgrade do
  let(:strategy) { double status: nil, cutover: nil, abort_upgrade: nil }
  let(:options) { Commander::Command::Options.new }

  before do
    allow(Subspace::Upgrade).to receive(:strategy_for).and_return strategy
    allow_any_instance_of(described_class).to receive(:say)
  end

  it "runs the requested phase against the environment's strategy" do
    options.cutover = true
    described_class.new ["production"], options

    expect(Subspace::Upgrade).to have_received(:strategy_for).with("production", options)
    expect(strategy).to have_received :cutover
  end

  it "maps --abort onto abort_upgrade" do
    options.abort = true
    described_class.new ["production"], options

    expect(strategy).to have_received :abort_upgrade
  end

  it "shows the status when no phase is given" do
    described_class.new ["production"], options

    expect(strategy).to have_received :status
  end

  it "refuses more than one phase", :aggregate_failures do
    options.cutover = true
    options.abort = true

    expect { described_class.new ["production"], options }.to raise_error SystemExit
    expect(Subspace::Upgrade).not_to have_received :strategy_for
  end

  it "refuses to run without an environment", :aggregate_failures do
    expect { described_class.new [], options }.to raise_error SystemExit
    expect(Subspace::Upgrade).not_to have_received :strategy_for
  end
end
