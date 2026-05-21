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

      @install_mock.expect :call, nil do
        flunk
      end
      with_stubs do
        FakeBrowserRunner.new.start
      end
    end

    private

    def with_stubs(&)
      BrowserInstaller.stub(:install, @install_mock, &)
    end
  end
end
