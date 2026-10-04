# frozen_string_literal: true

require "open3"
require "shellwords"

module Venetian
  # # \Executable
  #
  # Provides methods for locating the Playwright executable.
  module Executable
    class Executor # :nodoc:
      public :system, :exec

      def capture(*command)
        Open3.capture2e(*command)
      end
    end

    DEFAULT_DIR = File.expand_path(File.join(__dir__, "..", "..", "exe")) # :nodoc:
    INSTALL_DIR_ENV_VAR = "VENETIAN_INSTALL_DIR" # :nodoc:

    # # Unsupported Platform Error
    #
    # Raised when no platform targeted by this gem is supported by the Rubygems installation.
    class UnsupportedPlatformError < StandardError
      def initialize(platform) # :nodoc:
        super(unsupported_platform_message(platform))
      end

      private

      def unsupported_platform_message(platform)
        <<~MSG
          Playwright does not support the #{platform} platform.
          Supported platforms:
            #{supported_platforms}

          Set #{INSTALL_DIR_ENV_VAR} to the directory containing your playwright executable.
          See https://github.com/jmalcic/venetian for more details.
        MSG
      end

      def supported_platforms
        Upstream::NATIVE_PLATFORMS.keys
                                  .collect { |platform| "- #{platform}" }
                                  .join("\n  ")
      end
    end

    # # Executable Not Found Error
    #
    # Raised when the Playwright executable cannot be found for the current platform.
    class ExecutableNotFoundError < StandardError
      def initialize(reason, exe_dir: nil, exe_path: nil, cli_path: nil, platform: nil) # :nodoc:
        super(case reason
              in :directory_missing then directory_missing_message(exe_dir)
              in :executable_missing then executable_missing_message(exe_dir)
              in :missing_platform then unsupported_platform_message(platform, exe_dir)
              in :not_a_file then incomplete_message(exe_path, "#{exe_path} is not a file")
              in :not_executable then incomplete_message(exe_path, "#{exe_path} is not executable")
              in :cli_missing then incomplete_message(exe_path, "#{cli_path} is missing")
              end)
      end

      private

      def directory_missing_message(exe_dir)
        "#{INSTALL_DIR_ENV_VAR} is set to #{exe_dir} but that directory does not exist."
      end

      def executable_missing_message(exe_dir)
        "#{INSTALL_DIR_ENV_VAR} is set to #{exe_dir} but playwright was not found there."
      end

      def incomplete_message(exe_path, problem)
        <<~MSG
          The Playwright driver at #{File.dirname(exe_path)} is incomplete: #{problem}.

          Reinstall the gem, or check #{INSTALL_DIR_ENV_VAR} points to a complete driver.
        MSG
      end

      def unsupported_platform_message(platform, exe_dir)
        <<~MSG
          Cannot find the Playwright executable for #{platform} in #{exe_dir}.

          Make sure your Gemfile.lock includes this platform:
            bundle lock --add-platform #{platform}
            bundle install

          Or set #{INSTALL_DIR_ENV_VAR} to the directory containing your Playwright executable.
        MSG
      end
    end

    # # Unsupported Path Error
    #
    # Raised on Windows when the path to the Playwright executable contains an environment variable reference such as
    # +%USERNAME%+, as Ruby would then run the command with +cmd.exe+, which expands it.
    class UnsupportedPathError < StandardError
      def initialize(path) # :nodoc:
        super(<<~MSG)
          Cannot run Playwright from #{path} as Windows would expand the environment variable references in its path.

          Set #{INSTALL_DIR_ENV_VAR} to a directory without them (e.g. %NAME%) containing your Playwright executable.
        MSG
      end
    end

    module Command # :nodoc:
      TOKEN_PATTERN = /\\.?|%[A-Za-z_][A-Za-z0-9_]*.?|./m
      VARIABLE_REFERENCE_PATTERN = /\A%[A-Za-z_][A-Za-z0-9_]*%\z/

      def self.shelljoin(command)
        return command.shelljoin unless Gem.win_platform?

        command.collect { |arg| %("#{arg}") }
               .join(" ")
               .tap { |string| raise UnsupportedPathError, command.first if run_by_cmd?(string) }
      end

      def self.run_by_cmd?(string)
        string.scan(TOKEN_PATTERN).any? { |token| token.match?(VARIABLE_REFERENCE_PATTERN) }
      end
    end

    module Validations # :nodoc:
      private

      def validate!
        ensure_exe_dir_exists!
        ensure_gem_platform_supported! unless ENV.key?(INSTALL_DIR_ENV_VAR)
        ensure_executable_exists!
        ensure_exe_file!
        ensure_exe_executable!
        ensure_cli_path_exists!
      end

      def ensure_exe_dir_exists!
        raise ExecutableNotFoundError.new(:directory_missing, exe_dir: exe_dir) unless exe_dir_exists?
      end

      def ensure_gem_platform_supported!
        raise UnsupportedPlatformError, platform if gem_platforms_unsupported?
      end

      def ensure_executable_exists!
        return unless exe_path.nil?

        raise ExecutableNotFoundError.new ENV.key?(INSTALL_DIR_ENV_VAR) ? :executable_missing : :missing_platform,
                                          exe_dir: exe_dir, platform: platform
      end

      def ensure_exe_file!
        return if exe_file?

        raise ExecutableNotFoundError.new(:not_a_file, exe_path: exe_path)
      end

      def ensure_exe_executable!
        return if exe_executable?

        raise ExecutableNotFoundError.new(:not_executable, exe_path: exe_path)
      end

      def ensure_cli_path_exists!
        return if cli_path_exists?

        raise ExecutableNotFoundError.new(:cli_missing, exe_path: exe_path, cli_path: cli_path_for(exe_path))
      end
    end

    extend Validations

    class << self
      # Returns the path to the Node executable. Raises an error if the executable cannot be found.
      def path
        validate!

        exe_path
      end

      # Executes the Playwright executable with the given arguments.
      def execute(*args, echo: true, exception: true, **)
        [*base_command, *args].then do |command|
          # due to mysterious Windows behavior; see equivalent in `tailwindcss-ruby`
          next system(*args, exception:, echo:) if Gem.win_platform?

          puts command.shelljoin if echo
          begin
            executor.exec(*command)
          rescue StandardError
            exception ? raise : false
          end
        end
      end

      # Runs the Playwright executable with the given arguments.
      def system(*args, echo: true, exception: true, **)
        [*base_command, *args].then do |command|
          puts command.shelljoin if echo
          executor.system(*command,
                          exception:, **{ out: echo ? nil : File::NULL, err: echo ? nil : File::NULL }.compact)
        end
      end

      # Runs the Playwright executable with the given arguments, returning its combined output and status.
      def capture(*args, echo: true)
        [*base_command, *args].then do |command|
          puts command.shelljoin if echo
          executor.capture(*command).tap do |output, _|
            puts output if echo
          end
        end
      end

      # Returns the base command to execute Playwright.
      def base_command
        path.then { |path| [path, cli_path_for(path)] }
      end

      # Returns the base command as a single string, as expected by +:playwright_cli_executable_path+.
      def cli_command
        Command.shelljoin(base_command)
      end

      private

      def exe_dir_exists?
        File.directory?(exe_dir)
      end

      def exe_dir
        ENV[INSTALL_DIR_ENV_VAR] || DEFAULT_DIR
      end

      def exe_file?
        File.file?(exe_path.to_s)
      end

      def exe_executable?
        File.executable?(exe_path.to_s)
      end

      def cli_path_exists?
        File.file?(cli_path_for(exe_path))
      end

      def cli_path_for(exe_path)
        File.join(File.dirname(exe_path), "package", "cli.js")
      end

      def exe_path
        return custom_exe_path if ENV.key?(INSTALL_DIR_ENV_VAR)

        native_platforms.collect { |platform, info| File.join(exe_dir, platform, info.executable_name) }
                        .detect { |candidate| File.exist?(candidate) }
      end

      def custom_exe_path
        File.join(exe_dir, custom_exe_name).then { |path| path if File.exist?(path) }
      end

      def custom_exe_name
        Gem.win_platform? ? "node.exe" : "node"
      end

      def gem_platforms_unsupported?
        native_platforms.none?
      end

      def native_platforms
        return {} if musl? # musl isn't supported because official Linux Node binaries require glibc

        Upstream::NATIVE_PLATFORMS.select { |platform, _| Gem::Platform.match_gem?(Gem::Platform.new(platform), gem_name) }
      end

      def musl?
        Gem::Platform.local.then { |local| local.os == "linux" && local.version.to_s.start_with?("musl") }
      end

      def gem_name
        GEMSPEC&.name || "venetian"
      end

      def platform
        Gem::Platform.local.to_s
      end

      def executor
        @executor ||= Executor.new
      end
    end
  end
end
