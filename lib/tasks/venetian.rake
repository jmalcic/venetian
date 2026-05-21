# frozen_string_literal: true

namespace :venetian do
  desc <<~USAGE
    Install Playwright browsers. Pass a name to install a specific browser (e.g. venetian:install[chromium]), else installs default browsers.
  USAGE
  task :install, [:browser] do |_task, args|
    require "venetian"
    Venetian::BrowserInstaller.install(args[:browser])
  end
end
