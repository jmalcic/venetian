# frozen_string_literal: true

module Venetian
  module PlaywrightCreateExtensions # :nodoc:
    def initialize(options = {}, *)
      super({ playwright_cli_executable_path: Executable.base_command.shelljoin }.merge(options), *)
    end
  end
end

Capybara::Playwright::BrowserRunner::PlaywrightCreate.prepend(Venetian::PlaywrightCreateExtensions)
