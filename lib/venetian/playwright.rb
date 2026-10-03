# frozen_string_literal: true

require "playwright"

require "venetian/core"

module Venetian # :nodoc:
  # Starts Playwright using the bundled executable. Accepts the same arguments as +Playwright.create+,
  # so +:playwright_cli_executable_path+ can still be overridden.
  def self.start(**options, &)
    options[:playwright_cli_executable_path] ||= Executable.cli_command
    Playwright.create(**options, &)
  end
end
