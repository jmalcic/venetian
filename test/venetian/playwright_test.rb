# frozen_string_literal: true

require "test_helper"

module Venetian
  class PlaywrightTest < Minitest::Test
    BUNDLED_COMMAND = if Gem.win_platform?
                        '"/bundled/playwright" "/bundled/package/cli.js"'
                      else
                        "/bundled/playwright /bundled/package/cli.js"
                      end

    setup do
      @create_mock = Minitest::Mock.new
    end

    test "start injects bundled binary when no path given" do
      @create_mock.expect(:call, :execution, [], playwright_cli_executable_path: BUNDLED_COMMAND)

      with_stubbed_path do
        assert_equal :execution, Venetian.start
      end

      assert_mock @create_mock
    end

    test "start lets user supplied path take precedence" do
      @create_mock.expect(:call, :execution, [], playwright_cli_executable_path: "/custom")

      with_stubbed_path error: true do
        assert_equal :execution, Venetian.start(playwright_cli_executable_path: "/custom")
      end

      assert_mock @create_mock
    end

    test "start passes block through" do
      @create_mock.expect(:call, :result) { |**, &given| given.call(@create_mock) }
      @create_mock.expect(:chromium, true)

      with_stubbed_path do
        assert_equal :result, Venetian.start(&:chromium)
      end

      assert_mock @create_mock
    end

    private

    def with_stubbed_path(error: false, &)
      Executable.stub(:path, error ? -> { flunk "unexpected path lookup" } : "/bundled/playwright") do
        ::Playwright.stub(:create, @create_mock, &)
      end
    end
  end
end
