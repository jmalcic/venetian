# frozen_string_literal: true

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

      def dependencies_to_install
        @dependencies_to_install ||= {}
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

    # Installs a browser. Raises InstallError if installation fails.
    def self.install(browser = nil, install_dependencies: nil)
      Venetian.system "install", *browser&.to_s,
                      *("--with-deps" if install_dependencies?(browser, force: install_dependencies)),
                      exception: true, echo: debug?
    rescue StandardError => e
      raise InstallError, e.message
    end

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

    def self.dependencies_supported?(...) # :nodoc:
      warn "Venetian::BrowserInstaller.dependencies_supported? is deprecated; use dependencies_to_install? instead.",
           category: :deprecated, uplevel: 1
      dependencies_to_install?(...)
    end
  end
end
