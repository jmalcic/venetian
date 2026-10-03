# frozen_string_literal: true

require "test_helper"

module Venetian
  class ExecutableTest < Minitest::Test
    class ExecutorMock < Minitest::Mock
      def expect_system(retval, args = nil, **)
        if retval.is_a?(Class) && retval <= Exception
          expect(:system, nil) do |*actual_args, **actual_options|
            assert_equal [*Executable.base_command, *args], actual_args
            assert_equal Hash(**), actual_options
            raise retval
          end
        else
          expect(:system, retval, [*Executable.base_command, *args], **)
        end
      end
    end

    module Execution
      module Tests
        extend ActiveSupport::Concern

        included do
          test "system calls executor with base command and args" do
            mocking_exe_directory do
              @executor_mock.expect_system(true, ["foo"], exception: true)

              with_stubs do
                assert_output "#{Executable.base_command.shelljoin} foo\n" do
                  assert Executable.system "foo"
                end
              end
            end

            assert_mock @executor_mock
          end

          test "system calls executor and raises when exception is true" do
            mocking_exe_directory do
              @executor_mock.expect_system(StandardError)

              with_stubs do
                assert_raises StandardError do
                  Executable.system "foo"
                end
              end
            end

            assert_mock @executor_mock
          end

          test "system calls executor without raising when exception is false" do
            mocking_exe_directory do
              @executor_mock.expect_system(nil, ["foo"], exception: false)

              with_stubs do
                refute Executable.system "foo", exception: false
              end
            end

            assert_mock @executor_mock
          end

          test "system does not print when echo is false" do
            mocking_exe_directory do
              @executor_mock.expect_system(true, ["foo"], exception: true, out: File::NULL, err: File::NULL)

              with_stubs do
                assert_output "" do
                  assert Executable.system "foo", echo: false
                end
              end
            end

            assert_mock @executor_mock
          end

          test "execute calls exec with base command and args" do
            mocking_exe_directory do
              @executor_mock.expect(:exec, true, [*Executable.base_command, "foo"])

              with_stubs do
                assert_output "#{Executable.base_command.shelljoin} foo\n" do
                  assert Executable.execute "foo"
                end
              end
            end

            assert_mock @executor_mock
          end

          test "execute calls system on Windows" do
            mocking_exe_directory do
              @executor_mock.expect_system(true, ["foo"], exception: true)

              Gem.stub :win_platform?, true do
                with_stubs do
                  assert_output "#{Executable.base_command.shelljoin} foo\n" do
                    assert Executable.execute "foo"
                  end
                end
              end
            end

            assert_mock @executor_mock
          end

          test "execute does not print when echo is false" do
            mocking_exe_directory do
              @executor_mock.expect(:exec, true, [*Executable.base_command, "foo"])

              with_stubs do
                assert_output "" do
                  assert Executable.execute "foo", echo: false
                end
              end
            end

            assert_mock @executor_mock
          end

          test "execute returns false when exec raises and exception is false" do
            mocking_exe_directory do
              @executor_mock.expect(:exec, nil) { raise StandardError }

              with_stubs do
                refute Executable.execute("foo", exception: false, echo: false)
              end
            end

            assert_mock @executor_mock
          end

          test "execute re-raises when exec raises and exception is true" do
            mocking_exe_directory do
              @executor_mock.expect(:exec, nil) { raise StandardError, "boom" }

              with_stubs do
                assert_raises StandardError, match: /boom/ do
                  Executable.execute "foo", echo: false
                end
              end
            end

            assert_mock @executor_mock
          end
        end
      end
    end

    module CliCommand
      module Tests
        extend ActiveSupport::Concern

        included do
          test "cli command escapes arguments for a POSIX shell" do
            Executable.stub(:base_command, ["/home/Jane Doe/node", "/home/Jane Doe/package/cli.js"]) do
              Gem.stub(:win_platform?, false) do
                assert_equal "/home/Jane\\ Doe/node /home/Jane\\ Doe/package/cli.js", Executable.cli_command
              end
            end
          end

          test "cli command quotes arguments on Windows" do
            Executable.stub(:base_command, ["C:/Users/Jane Doe/node.exe", "C:/Users/Jane Doe/package/cli.js"]) do
              Gem.stub(:win_platform?, true) do
                assert_equal '"C:/Users/Jane Doe/node.exe" "C:/Users/Jane Doe/package/cli.js"', Executable.cli_command
              end
            end
          end

          test "cli command runs from a path needing quoting" do
            mocking_exe_directory do
              assert_pattern do
                capture_subprocess_io { system("#{Executable.cli_command} run-driver") } =>
                  ["#{Executable.base_command.last}\nrun-driver\n",]
              end
            end
          end
        end
      end
    end

    include Execution::Tests
    include CliCommand::Tests

    setup do
      @executor_mock = ExecutorMock.new
    end

    teardown do
      ENV.delete("VENETIAN_INSTALL_DIR")
    end

    test "returns absolute path to binary for current platform" do
      mocking_exe_directory do |expected_path|
        assert_equal expected_path, Executable.path
      end
    end

    test "raises executable not found when directory missing" do
      stubbing_exe_dir "/does/not/exist/at/all" do
        assert_raises Executable::ExecutableNotFoundError, match: /directory does not exist/ do
          Executable.path
        end
      end
    end

    test "raises unsupported platform error when no platform matches" do
      mocking_exe_directory plaform_matches: false do
        assert_raises Executable::UnsupportedPlatformError, match: /Playwright does not support the \S+ platform/ do
          Executable.path
        end
      end
    end

    test "raises executable not found when platform matches but file is missing" do
      mocking_exe_directory executable: false do
        assert_raises Executable::ExecutableNotFoundError, match: /Cannot find the Playwright executable/ do
          Executable.path
        end
      end
    end

    test "uses install directory from env var" do
      mocking_exe_directory stub_exe_dir: false do |path|
        with_mock_executable File.expand_path("#{path}/../elsewhere") do |exe_path|
          ENV["VENETIAN_INSTALL_DIR"] = File.expand_path("#{exe_path}/..")

          assert_equal exe_path, Executable.path
        end
      end
    end

    test "raises when executable missing from install directory from env var" do
      mocking_exe_directory stub_exe_dir: false do |path|
        with_mock_executable File.expand_path("#{path}/../elsewhere"), dir_only: true do
          ENV["VENETIAN_INSTALL_DIR"] = File.expand_path("#{path}/../elsewhere")
          assert_raises Executable::ExecutableNotFoundError, match: /playwright was not found there/ do
            Executable.path
          end
        end
      end
    end

    private

    def mocking_exe_directory(platform: local_platform, executable: true, plaform_matches: true,
                              stub_exe_dir: true, &block)
      with_tmpdir do |dir|
        Gem::Platform.stub(:match_gem?, plaform_matches) do
          next executable ? with_mock_executable(dir, platform: platform, &block) : yield unless stub_exe_dir

          stubbing_exe_dir dir do
            executable ? with_mock_executable(dir, platform: platform, &block) : yield
          end
        end
      end
    end

    def with_tmpdir(&)
      Dir.mktmpdir do |dir|
        File.join(dir, "Jane O'Doe (x86) & Jürgen")
            .tap { |subdir| FileUtils.mkdir_p(subdir) }
            .then(&)
      end
    end

    def with_mock_executable(path, platform: local_platform, dir_only: false, &)
      FileUtils.mkdir_p(File.join(path, platform.to_s))
      if dir_only
        yield
        return
      end

      create_fake_node_in(Pathname.new(path).join(platform.to_s)).to_s.then(&)
    end

    def create_fake_node_in(dir)
      if Gem.win_platform?
        dir.join("node.exe").tap { |path| FileUtils.cp(File.expand_path("../fixtures/print_args.exe", __dir__), path) }
      else
        dir.join("node").tap { |path| path.write("#!/bin/sh\nprintf '%s\\n' \"$@\"\n", perm: 0o755) }
      end
    end

    def stubbing_exe_dir(dir = nil, &)
      Executable.stub(:exe_dir, dir, &)
    end

    def local_platform
      Upstream::NATIVE_PLATFORMS.keys.detect { |platform| Gem::Platform.local =~ platform }
    end

    def with_stubs(&)
      Executable.stub :executor, @executor_mock, &
    end
  end
end
