# TODO...Get working. For some reason, these tasks can't be called in projects that include this gem.
namespace :provision do
  task :production do
    Dir.chdir "config/provision" do
      `ansible-playbook production.yml`
    end
  end

  task :qa do

  end

  task :dev do

  end

  # Deprecated, but some older projects still have staging environments
  task :staging do

  end
end
