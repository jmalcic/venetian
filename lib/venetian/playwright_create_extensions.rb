# frozen_string_literal: true

module Venetian
  module PlaywrightCreateExtensions # :nodoc:
    def initialize(options = {}, *)
      unless options[:playwright_cli_executable_path]
        options = options.merge(playwright_cli_executable_path: Executable.cli_command)
      end
      super
    end
  end
end

Capybara::Playwright::BrowserRunner::PlaywrightCreate.prepend(Venetian::PlaywrightCreateExtensions)
