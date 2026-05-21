# frozen_string_literal: true

require "capybara/playwright"

require "venetian/version"
require "venetian/upstream"
require "venetian/executable"
require "venetian/playwright_create_extensions"
require "venetian/browser_installer"
require "venetian/browser_runner_extensions"
require "venetian/gemspec"
require "venetian/railtie" if defined? Rails

# # Venetian
#
# Native Playwright driver for Capybara.
module Venetian
  class << self
    attr_accessor :auto_install_browsers
  end

  class Error < StandardError; end

  self.auto_install_browsers = true

  def self.execute(*, echo: true)
    Executable.execute(*, echo: echo)
  end
end
