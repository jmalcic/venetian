# frozen_string_literal: true

require "test_helper"

module Venetian
  class BrowserInstallerTest < Minitest::Test
    setup do
      @system_mock = Minitest::Mock.new
    end

    test "install executes correct command" do
      @system_mock.expect(:call, true, %w[install --with-deps], exception: true, echo: nil)
      with_stubs do
        BrowserInstaller.install
      end

      assert_mock @system_mock
    end

    test "install passes browser name" do
      @system_mock.expect(:call, true, %w[install firefox --with-deps], exception: true, echo: nil)
      with_stubs do
        BrowserInstaller.install(:firefox)
      end

      assert_mock @system_mock
    end

    test "install allows skipping dependenceies" do
      @system_mock.expect(:call, true, %w[install], exception: true, echo: nil)
      with_stubs do
        BrowserInstaller.install(install_dependencies: false)
      end

      assert_mock @system_mock
    end

    test "install raises on command failure" do
      @system_mock.expect(:call, nil) do
        raise StandardError, "This is really really really bad"
      end

      with_stubs do
        assert_raises BrowserInstaller::InstallError, match: /This is really really really bad/ do
          BrowserInstaller.install
        end
      end
      assert_mock @system_mock
    end

    private

    def with_stubs(&)
      Executable.stub(:system, @system_mock, &)
    end
  end
end
