namespace :provision do
  # Using staging as an environment is deprecated,
  # but some older projects still use it.
  Dir[Rails.root.join("config", "provision", "*.yml")].collect {|x| File.basename(x, ".yml")}.each do |env|
    desc "Provision #{env} server"
    task env do
      Dir.chdir "config/provision" do
        system "ansible-playbook #{env}.yml"
      end
    end
  end
end
