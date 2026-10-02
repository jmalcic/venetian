# frozen_string_literal: true

require "playwright"

require "venetian/version"
require "venetian/upstream"
require "venetian/executable"
require "venetian/browser_installer"
require "venetian/gemspec"

# # Venetian
#
# Native Playwright driver for Ruby.
module Venetian
  class << self
    attr_accessor :auto_install_browsers, :auto_install_dependencies
  end

  class Error < StandardError; end

  self.auto_install_browsers = true
  self.auto_install_dependencies = true

  def self.execute(*, echo: true, **)
    Executable.execute(*, echo: echo, **)
  end

  def self.system(*, echo: true, **)
    Executable.system(*, echo: echo, **)
  end

  # Starts Playwright using the bundled executable. Accepts the same arguments as +Playwright.create+,
  # so +:playwright_cli_executable_path+ can still be overridden.
  def self.start(**options, &)
    options[:playwright_cli_executable_path] ||= Executable.cli_command
    Playwright.create(**options, &)
  end
end
