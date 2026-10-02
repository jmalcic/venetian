# frozen_string_literal: true

require "capybara/playwright"

require "venetian/playwright"
require "venetian/playwright_create_extensions"
require "venetian/browser_runner_extensions"
require "venetian/railtie" if defined?(Rails::Railtie)
