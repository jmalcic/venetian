# frozen_string_literal: true

require "test_helper"

module Venetian
  class BrowserInstallerTest < Minitest::Test
    module Stubbing
      private

      def with_stubs(&)
        Executable.stub(:system, @system_mock, &)
      end
    end

    include Stubbing

    setup do
      @system_mock = Minitest::Mock.new
    end

    teardown do
      BrowserInstaller.instance_variable_set(:@dependencies_supported, nil)
    end

    test "install executes correct command" do
      @system_mock.expect(:call, true, %w[install-deps --dry-run], exception: false, echo: nil)
                  .expect(:call, true, %w[install --with-deps], exception: true, echo: nil)
      with_stubs do
        Venetian.with auto_install_dependencies: true do
          BrowserInstaller.install
        end
      end

      assert_mock @system_mock
    end

    test "install passes browser name" do
      @system_mock.expect(:call, true, %w[install-deps --dry-run], exception: false, echo: nil)
                  .expect(:call, true, %w[install firefox --with-deps], exception: true, echo: nil)
      with_stubs do
        Venetian.with auto_install_dependencies: true do
          BrowserInstaller.install(:firefox)
        end
      end

      assert_mock @system_mock
    end

    test "install allows skipping dependencies" do
      @system_mock.expect(:call, true, %w[install], exception: true, echo: nil)
      with_stubs do
        BrowserInstaller.install(install_dependencies: false)
      end

      assert_mock @system_mock
    end

    test "install raises on command failure" do
      @system_mock.expect(:call, true, %w[install-deps --dry-run], exception: false, echo: nil)
                  .expect(:call, nil) { raise StandardError, "This is really really really bad" }

      with_stubs do
        Venetian.with auto_install_dependencies: true do
          assert_raises BrowserInstaller::InstallError, match: /This is really really really bad/ do
            BrowserInstaller.install
          end
        end
      end

      assert_mock @system_mock
    end

    test "install omits dependencies when option is false" do
      @system_mock.expect(:call, true, %w[install], exception: true, echo: nil)
      with_stubs do
        Venetian.with auto_install_dependencies: true do
          BrowserInstaller.install(install_dependencies: false)
        end
      end

      assert_mock @system_mock
    end

    test "install omits dependencies when auto install dependencies is false" do
      @system_mock.expect(:call, true, %w[install], exception: true, echo: nil)
      with_stubs do
        Venetian.with auto_install_dependencies: false do
          BrowserInstaller.install
        end
      end

      assert_mock @system_mock
    end

    test "install omits dependencies when not supported" do
      @system_mock.expect(:call, false, %w[install-deps --dry-run], exception: false, echo: nil)
                  .expect(:call, true, %w[install], exception: true, echo: nil)
      with_stubs do
        Venetian.with auto_install_dependencies: true do
          BrowserInstaller.install
        end
      end

      assert_mock @system_mock
    end

    test "dependencies supported predicate returns true when dry-run exits zero" do
      @system_mock.expect(:call, true, %w[install-deps --dry-run], exception: false, echo: nil)

      with_stubs do
        assert_predicate BrowserInstaller, :dependencies_supported?
      end
      assert_mock @system_mock
    end

    test "dependencies supported predicate returns false when dry-run exits non-zero" do
      @system_mock.expect(:call, false, %w[install-deps --dry-run], exception: false, echo: nil)

      with_stubs do
        refute_predicate BrowserInstaller, :dependencies_supported?
      end
      assert_mock @system_mock
    end

    test "dependencies supported predicate memoized" do
      @system_mock.expect(:call, true, %w[install-deps --dry-run], exception: false, echo: nil)
                  .expect(:call, nil, %w[install-deps --dry-run], exception: false, echo: nil)

      with_stubs do
        BrowserInstaller.dependencies_supported?

        assert_predicate BrowserInstaller, :dependencies_supported?
        BrowserInstaller.dependencies_supported?(force: true)

        refute_predicate BrowserInstaller, :dependencies_supported?
      end

      assert_mock @system_mock
    end
  end
end
