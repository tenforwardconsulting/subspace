require 'fileutils'
class Subspace::Commands::Override < Subspace::Commands::Base
  def initialize(args, options)
    @role = args.first
    run
  end

  def run
    role_src = File.join gem_path, "ansible", "roles", @role
    if !File.exist? role_src
      say "Error, no such role #{@role}"
      exit
    end
    dest = File.join dest_dir, 'roles', @role
    if File.exist? dest
      say "Error, cowardly refusing to overwrite #{dest} - file exists"
      exit
    end
    FileUtils.cp_r role_src, dest
  end
end
