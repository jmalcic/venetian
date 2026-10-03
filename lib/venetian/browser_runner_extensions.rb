# frozen_string_literal: true

module Venetian
  module BrowserRunnerExtensions # :nodoc:
    ALTERNATIVE_DRIVER_OPTIONS = %i[playwright_cli_executable_path playwright_server_endpoint_url
                                    browser_server_endpoint_url].freeze

    def self.browser_to_preinstall_from(options)
      (options[:browser_type] || :chromium).to_sym if options.values_at(*ALTERNATIVE_DRIVER_OPTIONS).none?
    end

    def initialize(options = {}, *args)
      @venetian_browser = BrowserRunnerExtensions.browser_to_preinstall_from(options) if Venetian.auto_install_browsers
      super
    end

    def start
      BrowserInstaller.install(@venetian_browser) if @venetian_browser
      super
    end
  end
end

Capybara::Playwright::BrowserRunner.prepend(Venetian::BrowserRunnerExtensions)
