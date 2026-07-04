# frozen_string_literal: true

require "test_helper"
require "action_dispatch/system_test_case"
require "venetian/system_test_case_extension"

module Venetian
  class SystemTestCaseExtensionTest < Minitest::Test
    class FakeSystemTestCase < ActionDispatch::SystemTestCase
      prepend SystemTestCaseExtension

      driven_by :playwright
    end

    class OtherFakeSystemTestCase < ActionDispatch::SystemTestCase
      prepend SystemTestCaseExtension

      driven_by :playwright, options: { browser_type: :firefox }
    end

    class SystemTestCaseWithoutDriver < ActionDispatch::SystemTestCase
      prepend SystemTestCaseExtension
    end

    setup do
      @auto_install_browsers_was = Venetian.auto_install_browsers
      @test_case = Class.new(FakeSystemTestCase)
      @install_mock = Minitest::Mock.new
    end

    teardown do
      Venetian.auto_install_browsers = @auto_install_browsers_was
    end

    test "sets browser type for Playwright driver with option" do
      @test_case.driven_by(:playwright, options: { browser_type: :firefox })

      assert_equal :firefox, @test_case.venetian_browser_type
    end

    test "does not change browser type when no browser type in options" do
      assert_equal :chromium, @test_case.venetian_browser_type
    end

    test "does not set browser type for non-Playwright driver" do
      @test_case.driven_by(:cuprite, options: { browser_type: :firefox })

      assert_nil @test_case.venetian_browser_type
    end

    test "converts browser type to symbol" do
      @test_case.driven_by(:playwright, options: { browser_type: "firefox" })

      assert_equal :firefox, @test_case.venetian_browser_type
    end

    test "calls super" do
      assert_equal :playwright, @test_case.driver.name
    end

    test "installs browsers and disables autoinstallation" do
      Minitest::Runnable.stub :runnables, [FakeSystemTestCase, OtherFakeSystemTestCase, SystemTestCaseWithoutDriver] do
        Venetian.auto_install_browsers = true

        assert Venetian.auto_install_browsers
        @install_mock.expect(:call, true, [:chromium])
                     .expect(:call, true, [:firefox])
        with_stubs do
          @test_case.install_playwright_browsers
        end

        assert_mock @install_mock
        refute Venetian.auto_install_browsers
      end
    end

    test "does not disable autoinstallation if nothing to install" do
      Minitest::Runnable.stub :runnables, [] do
        Venetian.auto_install_browsers = true

        assert Venetian.auto_install_browsers
        with_stubs do
          @test_case.install_playwright_browsers
        end

        assert_mock @install_mock
        assert Venetian.auto_install_browsers
      end
    end

    private

    def with_stubs(&)
      BrowserInstaller.stub(:install, @install_mock, &)
    end
  end
end
