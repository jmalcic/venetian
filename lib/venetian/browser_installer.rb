# frozen_string_literal: true

module Venetian
  # # Browser Installer
  #
  # Installs browsers using the Playwright executable.
  class BrowserInstaller
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
    def self.install(browser = nil, install_dependencies: true)
      Venetian.system "install", *browser&.to_s, *("--with-deps" if install_dependencies),
                      exception: true, echo: ENV.fetch("VENETIAN_DEBUG", nil)
    rescue StandardError => e
      raise InstallError, e.message
    end
  end
end
