require 'subspace/upgrade'
class Subspace::Commands::Upgrade < Subspace::Commands::Base
  PHASES = {
    check: :check,
    status: :status,
    revendor: :revendor,
    init: :init,
    prepare: :prepare,
    copy_db: :copy_db,
    cutover: :cutover,
    finalize: :finalize,
    abort: :abort_upgrade,
    close_instance_ssh: :close_instance_ssh,
  }

  def initialize(args, options)
    @env = args.shift
    @options = options
    run
  end

  def run
    if @env.nil?
      say "Please provide an environment, e.g: subspace upgrade production --status"
      exit 1
    end

    requested = PHASES.keys.select { |phase| @options.__hash__[phase] }
    if requested.size > 1
      say "Pick exactly one phase: #{PHASES.keys.map { |phase| "--#{phase.to_s.tr "_", "-"}" }.join " "}"
      exit 1
    elsif requested.size == 0
      requested = [:status]
    end

    Subspace::Upgrade.strategy_for(@env, @options).send PHASES[requested.first]
  end
end
