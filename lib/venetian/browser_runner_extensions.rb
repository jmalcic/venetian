# frozen_string_literal: true

module Venetian
  module BrowserRunnerExtensions # :nodoc:
    def initialize(options = {}, *args)
      @venetian_browser_type = options[:browser_type] || :chromium
      super
    end

    def start
      BrowserInstaller.install(@venetian_browser_type) if Venetian.auto_install_browsers
      super
    end
  end
end

Capybara::Playwright::BrowserRunner.prepend(Venetian::BrowserRunnerExtensions)
