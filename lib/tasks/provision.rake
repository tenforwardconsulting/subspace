namespace :provision do
  # Using staging as an environment is deprecated,
  # but some older projects still use it.
  [:production, :qa, :dev, :staging].each do |env|
    desc "Provision #{env} server"
    task env do
      Dir.chdir "config/provision" do
        system "ansible-playbook #{env}.yml"
      end
    end
  end
end
