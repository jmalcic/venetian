# frozen_string_literal: true

module Venetian
  # # \Executable
  #
  # Provides methods for locating the Playwright executable.
  module Executable
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
      def initialize(reason, **context) # :nodoc:
        super(case reason
              in :directory_missing then directory_missing_message(context[:exe_dir])
              in :executable_missing then executable_missing_message(context[:exe_dir])
              else unsupported_platform_message(context[:platform], context[:exe_dir])
              end)
      end

      private

      def directory_missing_message(exe_dir)
        "#{INSTALL_DIR_ENV_VAR} is set to #{exe_dir} but that directory does not exist."
      end

      def executable_missing_message(exe_dir)
        "#{INSTALL_DIR_ENV_VAR} is set to #{exe_dir} but playwright was not found there."
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

    class << self
      # Returns the path to the Node executable. Raises an error if the executable cannot be found.
      def path
        ensure_exe_dir_exists!
        ensure_gem_platform_supported! unless ENV.key?(INSTALL_DIR_ENV_VAR)
        ensure_executable_exists!

        exe_path
      end

      # Executes the Playwright executable with the given arguments.
      def execute(*args, echo: true)
        [base_command, *args].then do |command|
          puts command.inspect if echo
          # due to mysterious Windows behavior; see equivalent in `tailwindcss-ruby`
          next system(*command, exception: true) if Gem.win_platform?

          exec(*command)
        end
      end

      # Runs the Playwright executable with the given arguments.
      def system(*args, echo: true, **)
        [*base_command, *args].then do |command|
          puts command.inspect if echo
          super(*command, exception: true)
        end
      end

      # Returns the base command to execute Playwright.
      def base_command
        [path, File.join(File.dirname(path), "package", "cli.js")]
      end

      private

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

      def exe_dir_exists?
        File.directory?(exe_dir)
      end

      def exe_dir
        ENV[INSTALL_DIR_ENV_VAR] || DEFAULT_DIR
      end

      def exe_path
        return custom_exe_path if ENV.key?(INSTALL_DIR_ENV_VAR)

        Upstream::NATIVE_PLATFORMS.select { |platform, _| Gem::Platform.match_gem?(Gem::Platform.new(platform), GEMSPEC.name) }
                                  .collect { |platform, _info| File.join(exe_dir, platform, "node") }
                                  .detect { |candidate| File.exist?(candidate) }
      end

      def custom_exe_path
        File.join(exe_dir, "node").then { |path| path if File.exist?(path) }
      end

      def gem_platforms_unsupported?
        Upstream::NATIVE_PLATFORMS.keys.none? { |platform| Gem::Platform.match_gem?(Gem::Platform.new(platform), GEMSPEC.name) }
      end

      def platform
        Gem::Platform.local.to_s
      end
    end
  end
end
