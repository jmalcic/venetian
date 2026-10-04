# frozen_string_literal: true

require "test_helper"

module Venetian
  class PlaywrightCreateExtensionsTest < Minitest::Test
    class TestPlaywrightCreate < Capybara::Playwright::BrowserRunner::PlaywrightCreate
      attr_reader :playwright_cli_executable_path, :browser_type
    end

    BUNDLED_COMMAND = if Gem.win_platform?
                        '"/bundled/playwright" "/bundled/package/cli.js"'
                      else
                        "/bundled/playwright /bundled/package/cli.js"
                      end

    test "injects bundled binary when no path given" do
      with_stubbed_path do
        assert_equal BUNDLED_COMMAND, TestPlaywrightCreate.new({}).playwright_cli_executable_path
      end
    end

    test "user supplied path takes precedence" do
      with_stubbed_path error: true do
        assert_equal "/custom/playwright",
                     TestPlaywrightCreate.new(playwright_cli_executable_path: "/custom/playwright")
                                         .playwright_cli_executable_path
      end
    end

    test "other options pass through unchanged" do
      with_stubbed_path do
        assert_equal :firefox, TestPlaywrightCreate.new(browser_type: :firefox).browser_type
      end
    end

    test "does not modify the options passed in" do
      with_stubbed_path do
        assert_equal BUNDLED_COMMAND,
                     TestPlaywrightCreate.new({ browser_type: :chromium }.freeze).playwright_cli_executable_path
      end
    end

    private

    def with_stubbed_path(error: false, &)
      Executable.stub(:path, error ? -> { flunk "unexpected path lookup" } : "/bundled/playwright", &)
    end
  end
end
