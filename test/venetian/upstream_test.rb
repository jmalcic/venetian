# frozen_string_literal: true

require "test_helper"

module Venetian
  class UpstreamTest < Minitest::Test
    test "playwright core url uses the advertised Playwright version" do
      assert_match COMPATIBLE_PLAYWRIGHT_VERSION, Upstream.playwright_core_url
    end

    test "client dependency allows later patches of the advertised Playwright minor version" do
      assert client_requirement.satisfied_by?(Gem::Version.new("#{major}.#{minor}.9"))
    end

    test "client dependency excludes the next Playwright minor version" do
      refute client_requirement.satisfied_by?(Gem::Version.new("#{major}.#{minor.succ}.0"))
    end

    test "client dependency excludes the next Playwright major version" do
      refute client_requirement.satisfied_by?(Gem::Version.new("#{major.succ}.0.0"))
    end

    private

    def client_requirement
      Gem.loaded_specs
         .fetch("venetian")
         .dependencies
         .detect { |dependency| dependency.name == "playwright-ruby-client" }
         .requirement
    end

    def major
      Gem::Version.new(COMPATIBLE_PLAYWRIGHT_VERSION).segments[0]
    end

    def minor
      Gem::Version.new(COMPATIBLE_PLAYWRIGHT_VERSION).segments[1]
    end
  end
end
