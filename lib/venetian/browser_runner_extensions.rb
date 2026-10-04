# frozen_string_literal: true

module Venetian
  module BrowserRunnerExtensions # :nodoc:
    ALTERNATIVE_DRIVER_OPTIONS = %i[playwright_cli_executable_path playwright_server_endpoint_url
                                    browser_server_endpoint_url].freeze
    SYSTEM_CHANNEL_PATTERN = /\A(chrome|msedge)/

    def self.browser_to_preinstall_from(options)
      return if options.values_at(*ALTERNATIVE_DRIVER_OPTIONS, :executablePath).any?
      return if options[:channel].to_s.match?(SYSTEM_CHANNEL_PATTERN)

      (options[:channel] || options[:browser_type] || :chromium).to_sym
    end

    def initialize(options = {}, *args)
      @venetian_browser = BrowserRunnerExtensions.browser_to_preinstall_from(options)
      super
    end

    def start
      BrowserInstaller.install(@venetian_browser) if @venetian_browser && Venetian.auto_install_browsers
      super
    end
  end
end

Capybara::Playwright::BrowserRunner.prepend(Venetian::BrowserRunnerExtensions)
