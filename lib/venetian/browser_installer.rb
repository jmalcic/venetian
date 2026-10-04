# frozen_string_literal: true

require "pathname"
require "tmpdir"

module Venetian
  # # Browser Installer
  #
  # Installs browsers using the Playwright executable.
  class BrowserInstaller
    class << self
      private

      def install_dependencies?(browser = nil, force: nil)
        return force unless force.nil?

        Venetian.auto_install_dependencies && dependencies_to_install?(browser)
      end

      def install_dry_run(browser = nil)
        Executable.capture("install-deps", *browser&.to_s, "--dry-run", echo: debug?)
      end

      def install_into_browsers_path(browser, deps: nil)
        if browsers_to_install.fetch(browser) { browsers_path_writable? }
          Venetian.system "install", *browser, *("--with-deps" if deps), exception: true, echo: debug?
        elsif deps
          Venetian.system "install-deps", *browser, exception: true, echo: debug?
        end
        browsers_to_install[browser] = false
        dependencies_to_install[browser] = false if deps
      end

      def browsers_path_writable?
        [expanded_browsers_path, expanded_browsers_path.join(LINKS_DIRECTORY)].all? do |path|
          Dir.mktmpdir(WRITE_PROBE_PREFIX, path.ascend.find(&:directory?)) do
            true
          end
        end
      rescue SystemCallError
        false
      end

      def default_cache_path
        if Gem.win_platform?
          env_path("LOCALAPPDATA") || Pathname(Dir.home).join("AppData", "Local")
        elsif Gem::Platform.local.os == "darwin"
          Pathname(Dir.home).join("Library", "Caches")
        else
          env_path("XDG_CACHE_HOME") || Pathname(Dir.home).join(".cache")
        end
      end

      def env_path(name)
        return if (path = ENV.fetch(name, "")).empty?

        Pathname(path)
      end

      def dependencies_to_install
        @dependencies_to_install ||= {}
      end

      def browsers_to_install
        @browsers_to_install ||= {}
      end

      def with_install_lock
        File.open(File.join(Dir.tmpdir, "venetian-#{Process.uid}.lock"), File::RDWR | File::CREAT, 0o600) do |file|
          file.flock(File::LOCK_EX)
          yield
        end
      end

      def debug?
        ENV.fetch("VENETIAN_DEBUG", nil)
      end
    end

    # # Install Error
    #
    # Raised when the installation fails for some reason.
    class InstallError < StandardError
      INSTALL_FAILED_MESSAGE = "Playwright install failed. Run `rake venetian:install` manually."

      def initialize(message = nil)
        super([INSTALL_FAILED_MESSAGE, *message].join(": "))
      end
    end

    # Installs a browser, unless it and any dependencies are already installed. Playwright skips browsers already in the
    # browsers path, and if that's read-only (e.g. a prepopulated cache), only dependencies are installed. Raises
    # InstallError if installation fails.
    def self.install(browser = nil, install_dependencies: nil)
      with_install_lock do
        install_into_browsers_path(browser&.to_s, deps: install_dependencies?(browser, force: install_dependencies))
      end
    rescue StandardError => e
      raise InstallError, e.message
    end

    LINKS_DIRECTORY = ".links" # :nodoc:
    WRITE_PROBE_PREFIX = ".venetian-write-probe" # :nodoc:

    # Output from a dry run where Playwright couldn't spawn its package manager, so has no way to install dependencies.
    NO_PACKAGE_MANAGER_OUTPUT = "ENOENT" # :nodoc:

    # Returns true if Playwright's dependency installer has something to install on the current OS for a browser,
    # or for the default browsers if none given.
    #
    # On Linux, the dry run simulates the install with the package manager, exiting non-zero if packages are missing or
    # if it can't simulate (e.g. no package lists yet, which the installer fixes by updating them first), unless there's
    # no package manager it can use. On Windows, the dry run only prints the command it would run, so there is always
    # something to install.
    def self.dependencies_to_install?(browser = nil, force: false)
      return true if Gem.win_platform?

      dependencies_to_install.delete(browser&.to_s) if force
      dependencies_to_install.fetch(browser&.to_s) do |key|
        dependencies_to_install[key] = install_dry_run(browser).then do |output, status|
          !status.success? && !output.include?(NO_PACKAGE_MANAGER_OUTPUT)
        end
      end
    end

    def self.browsers_path # :nodoc:
      case ENV.fetch("PLAYWRIGHT_BROWSERS_PATH", "")
      when "" then default_cache_path.join("ms-playwright")
      when "0" then Pathname(Executable.base_command.last).dirname.join(".local-browsers")
      else Pathname(ENV.fetch("PLAYWRIGHT_BROWSERS_PATH"))
      end
    end

    def self.expanded_browsers_path # :nodoc:
      browsers_path.expand_path(ENV.fetch("INIT_CWD", nil) || Dir.pwd)
    end

    def self.dependencies_supported?(...) # :nodoc:
      warn "Venetian::BrowserInstaller.dependencies_supported? is deprecated; use dependencies_to_install? instead.",
           category: :deprecated, uplevel: 1
      dependencies_to_install?(...)
    end
  end
end
