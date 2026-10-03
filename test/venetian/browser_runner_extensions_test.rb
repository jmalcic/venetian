# frozen_string_literal: true

require "test_helper"

module Venetian
  class BrowserRunnerExtensionsTest < Minitest::Test
    class FakeBrowserRunner
      def initialize(options = {}, **kwargs); end

      def start; end

      prepend BrowserRunnerExtensions
    end

    setup do
      Venetian.auto_install_browsers.then do |value|
        self.class.teardown { Venetian.auto_install_browsers = value }
      end
      @install_mock = Minitest::Mock.new
    end

    test "start installs the configured browser" do
      @install_mock.expect :call, true, [:firefox]
      with_stubs do
        FakeBrowserRunner.new({ browser_type: :firefox }).start
      end

      assert_mock @install_mock
    end

    test "start defaults to chromium when no browser type given" do
      @install_mock.expect :call, true, [:chromium]
      with_stubs do
        FakeBrowserRunner.new.start
      end

      assert_mock @install_mock
    end

    test "start skips install when auto install browsers is false" do
      Venetian.auto_install_browsers = false

      with_stubs error: true do
        FakeBrowserRunner.new.start
      end
    end

    test "browser to preinstall is the configured browser" do
      assert_equal :firefox, BrowserRunnerExtensions.browser_to_preinstall_from(browser_type: :firefox)
    end

    test "browser to preinstall defaults to chromium" do
      assert_equal :chromium, BrowserRunnerExtensions.browser_to_preinstall_from({})
    end

    BrowserRunnerExtensions::ALTERNATIVE_DRIVER_OPTIONS.each do |option|
      test "no browser to preinstall when #{option} given" do
        assert_nil BrowserRunnerExtensions.browser_to_preinstall_from(browser_type: :firefox, option => "elsewhere")
      end

      test "start skips install when #{option} given" do
        with_stubs error: true do
          FakeBrowserRunner.new({ option => "/elsewhere" }).start
        end
      end
    end

    private

    def with_stubs(error: false, &)
      BrowserInstaller.stub(:install, error ? proc { flunk } : @install_mock, &)
    end
  end
end
