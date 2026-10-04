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

      def expect_install_deps(*args)
        expect(:system, true, [*BASE_COMMAND, "install-deps", *args], exception: true, out: File::NULL, err: File::NULL)
      end
    end

    module Stubbing
      private

      def with_stubs(error: false, &)
        Executable.stub(:base_command, error ? -> { raise error } : BASE_COMMAND) do
          Executable.stub(:executor, @executor_mock, &)
        end
      end

      def with_env(**values)
        original = ENV.to_h.slice(*values.keys.collect(&:to_s))
        values.each { |name, value| ENV[name.to_s] = value&.to_s }
        yield
      ensure
        values.each_key { |name| ENV[name.to_s] = original[name.to_s] }
      end

      def with_read_only_browsers_path(&)
        BrowserInstaller.stub(:browsers_path_writable?, false, &)
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

    module Reuse
      module Tests
        extend ActiveSupport::Concern

        included do
          test "install remembers installed browsers" do
            @executor_mock.expect_install("firefox")
            with_stubs do
              2.times { BrowserInstaller.install(:firefox, install_dependencies: false) }
            end

            assert_mock @executor_mock
          end

          test "install installs only dependencies for installed browsers" do
            @executor_mock.expect_install("firefox")
            @executor_mock.expect_install_deps("firefox")
            with_stubs do
              BrowserInstaller.install(:firefox, install_dependencies: false)
              BrowserInstaller.install(:firefox, install_dependencies: true)
            end

            assert_mock @executor_mock
          end

          test "install skips browsers when browsers path is read-only" do
            with_stubs do
              with_read_only_browsers_path do
                BrowserInstaller.install(:firefox, install_dependencies: false)
              end
            end

            assert_mock @executor_mock
          end

          test "install installs only dependencies when browsers path is read-only" do
            @executor_mock.expect_install_deps("firefox")
            with_stubs do
              with_read_only_browsers_path do
                BrowserInstaller.install(:firefox, install_dependencies: true)
              end
            end

            assert_mock @executor_mock
          end

          test "no dependencies to install after installing them" do
            @executor_mock.expect_dry_run MISSING_OUTPUT
            @executor_mock.expect_install("--with-deps")
            with_stubs do
              Venetian.with auto_install_dependencies: true do
                BrowserInstaller.install
              end

              refute_predicate BrowserInstaller, :dependencies_to_install?
            end

            assert_mock @executor_mock
          end

          test "install serializes concurrent installations" do
            installing = Queue.new
            overlapped = false
            install = lambda do |*, **|
              overlapped ||= !installing.empty?
              installing << true
              sleep 0.1
              installing.pop
            end

            with_stubs do
              Venetian.stub(:system, install) do
                2.times.collect { Thread.new { BrowserInstaller.install(install_dependencies: true) } }.each(&:join)
              end
            end

            refute overlapped
          end
        end
      end
    end

    module BrowsersPath
      module Tests
        extend ActiveSupport::Concern

        included do
          test "browsers path from env var" do
            assert_equal @browsers_path, BrowserInstaller.browsers_path
          end

          test "browsers path keeps relative env var" do
            with_env PLAYWRIGHT_BROWSERS_PATH: "browsers" do
              assert_equal Pathname("browsers"), BrowserInstaller.browsers_path
            end
          end

          test "expanded browsers path resolves relative env var against init cwd" do
            with_env PLAYWRIGHT_BROWSERS_PATH: "browsers", INIT_CWD: @browsers_path do
              assert_equal @browsers_path.join("browsers"), BrowserInstaller.expanded_browsers_path
            end
          end

          test "expanded browsers path resolves relative env var against working directory without init cwd" do
            with_env PLAYWRIGHT_BROWSERS_PATH: "browsers", INIT_CWD: nil do
              Dir.chdir(@browsers_path) do
                assert_equal Pathname.pwd.join("browsers"), BrowserInstaller.expanded_browsers_path
              end
            end
          end

          test "browsers path inside driver package when env var is 0" do
            with_env PLAYWRIGHT_BROWSERS_PATH: 0 do
              with_stubs do
                assert_equal Pathname("/bundled/package/.local-browsers"), BrowserInstaller.browsers_path
              end
            end
          end

          test "browsers path in XDG cache on Linux" do
            with_env PLAYWRIGHT_BROWSERS_PATH: nil, XDG_CACHE_HOME: @browsers_path do
              on_platform "x86_64-linux" do
                assert_equal @browsers_path.join("ms-playwright"), BrowserInstaller.browsers_path
              end
            end
          end

          test "browsers path in home cache on Linux without XDG cache" do
            with_env PLAYWRIGHT_BROWSERS_PATH: nil, XDG_CACHE_HOME: nil do
              on_platform "x86_64-linux" do
                assert_equal Pathname(Dir.home).join(".cache", "ms-playwright"), BrowserInstaller.browsers_path
              end
            end
          end

          test "browsers path in caches on macOS" do
            with_env PLAYWRIGHT_BROWSERS_PATH: nil do
              on_platform "arm64-darwin" do
                assert_equal Pathname(Dir.home).join("Library", "Caches", "ms-playwright"),
                             BrowserInstaller.browsers_path
              end
            end
          end

          test "browsers path in local app data on Windows" do
            with_env PLAYWRIGHT_BROWSERS_PATH: nil, LOCALAPPDATA: @browsers_path do
              Gem.stub :win_platform?, true do
                assert_equal @browsers_path.join("ms-playwright"), BrowserInstaller.browsers_path
              end
            end
          end

          test "browsers path writable" do
            assert_predicate BrowserInstaller, :browsers_path_writable?
            assert_empty @browsers_path.children
          end

          test "browsers path writable when it does not exist yet" do
            with_env PLAYWRIGHT_BROWSERS_PATH: @browsers_path.join("missing", "ms-playwright") do
              assert_predicate BrowserInstaller, :browsers_path_writable?
            end
          end

          test "browsers path not writable when read-only" do
            skip_unless_permissions_apply

            with_read_only @browsers_path do
              refute_predicate BrowserInstaller, :browsers_path_writable?
            end
          end

          test "browsers path not writable when links are read-only" do
            skip_unless_permissions_apply

            with_read_only @browsers_path.join(BrowserInstaller::LINKS_DIRECTORY).tap(&:mkpath) do
              refute_predicate BrowserInstaller, :browsers_path_writable?
            end
          end
        end

        private

        def skip_unless_permissions_apply
          skip "Permissions don't apply to root" if Process.uid.zero?
          skip "Permissions are ACLs on Windows" if Gem.win_platform?
        end

        def with_read_only(path)
          path.chmod(0o555)
          yield
        ensure
          path.chmod(0o755)
        end

        def on_platform(platform, &)
          Gem.stub :win_platform?, false do
            Gem::Platform.stub(:local, Gem::Platform.new(platform), &)
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
    include Reuse::Tests
    include BrowsersPath::Tests
    include DependencyDetection::Tests

    setup do
      @executor_mock = ExecutorMock.new
      @browsers_path = Pathname(Dir.mktmpdir)
      @original_browsers_path = ENV.fetch("PLAYWRIGHT_BROWSERS_PATH", nil)
      ENV["PLAYWRIGHT_BROWSERS_PATH"] = @browsers_path.to_path
    end

    teardown do
      ENV["PLAYWRIGHT_BROWSERS_PATH"] = @original_browsers_path
      @browsers_path.rmtree
      BrowserInstaller.send(:dependencies_to_install).clear
      BrowserInstaller.send(:browsers_to_install).clear
    end
  end
end
