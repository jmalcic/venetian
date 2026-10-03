# frozen_string_literal: true

require "test_helper"

module Venetian
  class BrowserInstallerTest < Minitest::Test
    BASE_COMMAND = %w[/bundled/node /bundled/package/cli.js].freeze

    class ExecutorMock < Minitest::Mock
      def expect_dry_run(output, succeeds: false, browser: nil)
        expect(:capture, [output, Data.define(:success?).new(succeeds)],
               [*BASE_COMMAND, "install-deps", *browser, "--dry-run"])
      end

      def expect_install(*args)
        expect(:system, true, [*BASE_COMMAND, "install", *args], exception: true, out: File::NULL, err: File::NULL)
      end
    end

    module Stubbing
      private

      def with_stubs(error: false, &)
        Executable.stub(:base_command, error ? -> { raise error } : BASE_COMMAND) do
          Executable.stub(:executor, @executor_mock, &)
        end
      end
    end

    MISSING_OUTPUT = "Missing system dependencies (2):\n  libnss3\n  libxss1\n"
    INSTALLED_OUTPUT = "All system dependencies are installed.\n"
    SIMULATION_FAILED_OUTPUT = "Error: 'apt-get install -s' exited with code 100:\n" \
                               "E: Unable to locate package libnss3\n"
    UNAVAILABLE_OUTPUT = "Error: Failed to run 'apt-get install -s' to simulate dependency install: " \
                         "spawn apt-get ENOENT\n"

    module Installation
      module Tests
        extend ActiveSupport::Concern

        included do
          test "install executes correct command" do
            @executor_mock.expect_dry_run MISSING_OUTPUT
            @executor_mock.expect_install("--with-deps")
            with_stubs do
              Venetian.with auto_install_dependencies: true do
                BrowserInstaller.install
              end
            end

            assert_mock @executor_mock
          end

          test "install passes browser name" do
            @executor_mock.expect_dry_run MISSING_OUTPUT, browser: "firefox"
            @executor_mock.expect_install("firefox", "--with-deps")
            with_stubs do
              Venetian.with auto_install_dependencies: true do
                BrowserInstaller.install(:firefox)
              end
            end

            assert_mock @executor_mock
          end

          test "install raises on command failure" do
            @executor_mock.expect_dry_run MISSING_OUTPUT
            @executor_mock.expect(:system, nil) do
              raise StandardError, "This is really really really bad"
            end

            with_stubs do
              Venetian.with auto_install_dependencies: true do
                assert_raises BrowserInstaller::InstallError, match: /This is really really really bad/ do
                  BrowserInstaller.install
                end
              end
            end

            assert_mock @executor_mock
          end

          test "install raises install error when dependency check fails" do
            with_stubs error: Executable::ExecutableNotFoundError.new(:directory_missing) do
              Venetian.with auto_install_dependencies: true do
                assert_raises BrowserInstaller::InstallError, match: /directory does not exist/ do
                  BrowserInstaller.install
                end
              end
            end

            assert_mock @executor_mock
          end

          test "install omits dependencies when option is false" do
            @executor_mock.expect_install
            with_stubs do
              Venetian.with auto_install_dependencies: true do
                BrowserInstaller.install(install_dependencies: false)
              end
            end

            assert_mock @executor_mock
          end

          test "install includes dependencies without checking when option is true" do
            @executor_mock.expect_install("--with-deps")
            with_stubs do
              Venetian.with auto_install_dependencies: false do
                BrowserInstaller.install(install_dependencies: true)
              end
            end

            assert_mock @executor_mock
          end

          test "install omits dependencies when auto install dependencies is false" do
            @executor_mock.expect_install
            with_stubs do
              Venetian.with auto_install_dependencies: false do
                BrowserInstaller.install
              end
            end

            assert_mock @executor_mock
          end

          test "install omits dependencies when none to install" do
            @executor_mock.expect_dry_run INSTALLED_OUTPUT, succeeds: true
            @executor_mock.expect_install
            with_stubs do
              Venetian.with auto_install_dependencies: true do
                BrowserInstaller.install
              end
            end

            assert_mock @executor_mock
          end

          test "install omits dependencies when no package manager" do
            @executor_mock.expect_dry_run UNAVAILABLE_OUTPUT
            @executor_mock.expect_install
            with_stubs do
              Venetian.with auto_install_dependencies: true do
                BrowserInstaller.install
              end
            end

            assert_mock @executor_mock
          end
        end
      end
    end

    module DependencyDetection
      module Tests
        extend ActiveSupport::Concern

        included do
          test "dependencies to install when dry run lists missing packages" do
            @executor_mock.expect_dry_run MISSING_OUTPUT

            with_stubs do
              assert_predicate BrowserInstaller, :dependencies_to_install?
            end
            assert_mock @executor_mock
          end

          test "dependencies to install when dry run cannot simulate the install" do
            @executor_mock.expect_dry_run SIMULATION_FAILED_OUTPUT

            with_stubs do
              assert_predicate BrowserInstaller, :dependencies_to_install?
            end
            assert_mock @executor_mock
          end

          test "no dependencies to install when dry run succeeds" do
            @executor_mock.expect_dry_run INSTALLED_OUTPUT, succeeds: true

            with_stubs do
              refute_predicate BrowserInstaller, :dependencies_to_install?
            end
            assert_mock @executor_mock
          end

          test "no dependencies to install without a package manager" do
            @executor_mock.expect_dry_run UNAVAILABLE_OUTPUT

            with_stubs do
              refute_predicate BrowserInstaller, :dependencies_to_install?
            end
            assert_mock @executor_mock
          end

          test "dependencies to install on Windows without a dry run" do
            Gem.stub :win_platform?, true do
              with_stubs do
                assert_predicate BrowserInstaller, :dependencies_to_install?
              end
            end

            assert_mock @executor_mock
          end

          test "dependencies to install memoized per browser" do
            @executor_mock.expect_dry_run INSTALLED_OUTPUT, succeeds: true, browser: "chromium"
            @executor_mock.expect_dry_run MISSING_OUTPUT, browser: "firefox"

            with_stubs do
              BrowserInstaller.dependencies_to_install?(:chromium)

              refute BrowserInstaller.dependencies_to_install?("chromium")
              assert BrowserInstaller.dependencies_to_install?(:firefox)
            end
            assert_mock @executor_mock
          end

          test "dependencies to install rechecked when forced" do
            @executor_mock.expect_dry_run MISSING_OUTPUT
            @executor_mock.expect_dry_run INSTALLED_OUTPUT, succeeds: true

            with_stubs do
              BrowserInstaller.dependencies_to_install?

              assert_predicate BrowserInstaller, :dependencies_to_install?
              refute BrowserInstaller.dependencies_to_install?(force: true)
            end
            assert_mock @executor_mock
          end

          test "dependencies supported is a deprecated alias" do
            @executor_mock.expect_dry_run MISSING_OUTPUT

            with_stubs do
              assert_output nil, /dependencies_supported\? is deprecated/ do
                assert_predicate BrowserInstaller, :dependencies_supported?
              end
            end
            assert_mock @executor_mock
          end

          test "dependencies supported removed by 1.0" do
            flunk "Remove the deprecated BrowserInstaller.dependencies_supported? before releasing 1.0" unless
              Gem::Version.new(VERSION) < Gem::Version.new("1.0") ||
              !BrowserInstaller.respond_to?(:dependencies_supported?)
          end
        end
      end
    end

    include Stubbing
    include Installation::Tests
    include DependencyDetection::Tests

    setup do
      @executor_mock = ExecutorMock.new
    end

    teardown do
      BrowserInstaller.send(:dependencies_to_install).clear
    end
  end
end
