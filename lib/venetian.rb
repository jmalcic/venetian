# frozen_string_literal: true

require "capybara/playwright"

require "venetian/playwright"
require "venetian/playwright_create_extensions"
require "venetian/browser_runner_extensions"
require "venetian/railtie" if defined?(Rails::Railtie)

# # Venetian
#
# Native Playwright driver for Ruby.
module Venetian
  class << self
    attr_accessor :auto_install_browsers
  end

  self.auto_install_browsers = true
end
