# frozen_string_literal: true

module Venetian
  # # Browser Installer
  #
  # Installs browsers using the Playwright executable.
  class BrowserInstaller
    class << self
      private

      def install_dependencies?
        Venetian.auto_install_dependencies && dependencies_supported?
      end

      def install_dry_run
        Venetian.system "install-deps", "--dry-run", exception: false, echo: ENV.fetch("VENETIAN_DEBUG", nil)
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
    def self.install(browser = nil, install_dependencies: install_dependencies?)
      Venetian.system "install", *browser&.to_s, *("--with-deps" if install_dependencies),
                      exception: true, echo: ENV.fetch("VENETIAN_DEBUG", nil)
    rescue StandardError => e
      raise InstallError, e.message
    end

    # Returns true if the current OS supports Playwright's dependency installer.
    def self.dependencies_supported?(force: false)
      return @dependencies_supported unless @dependencies_supported.nil? || force

      @dependencies_supported = install_dry_run || false
    end
  end
end
