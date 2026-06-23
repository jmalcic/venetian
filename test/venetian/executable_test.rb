# frozen_string_literal: true

require "test_helper"

module Venetian
  class ExecutableTest < Minitest::Test
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
      Dir.mktmpdir do |dir|
        Gem::Platform.stub(:match_gem?, plaform_matches) do
          next executable ? with_mock_executable(dir, platform: platform, &block) : yield unless stub_exe_dir

          stubbing_exe_dir dir do
            executable ? with_mock_executable(dir, platform: platform, &block) : yield
          end
        end
      end
    end

    def with_mock_executable(path, platform: local_platform, dir_only: false, &)
      FileUtils.mkdir_p(File.join(path, platform.to_s))
      if dir_only
        yield
        return
      end

      File.join(path, platform.to_s, "node")
          .tap { |exe_path| FileUtils.touch(exe_path) }
          .tap { |exe_path| FileUtils.chmod(0o755, exe_path) }
          .then(&)
    end

    def stubbing_exe_dir(dir = nil, &)
      Executable.stub(:exe_dir, dir, &)
    end

    def local_platform
      Gem::Platform.local.dup.tap { it.version = nil }
    end
  end
end
