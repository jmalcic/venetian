# frozen_string_literal: true

require "playwright"

module Venetian
  # # \Upstream
  #
  # Provides platform mappings and URLs for Playwright.
  module Upstream
    # map of gem platform strings to Playwright CDN platform strings and executable names inside the driver zip
    NATIVE_PLATFORMS = {
      "x86_64-linux" => "linux",
      "aarch64-linux" => "linux-arm64",
      "x86_64-darwin" => "mac",
      "arm64-darwin" => "mac-arm64",
      "x64-mingw-ucrt" => "win32_x64"
    }.freeze

    # base for driver download URLs
    BASE_URL = "https://playwright.azureedge.net/builds/driver"

    # Returns the URL to download the driver for the given platform.
    def self.driver_download_url(playwright_platform)
      "#{BASE_URL}/playwright-#{Playwright::COMPATIBLE_PLAYWRIGHT_VERSION}-#{playwright_platform}.zip"
    end

    # Returns a hash that maps platforms to download URLs.
    def self.download_urls
      NATIVE_PLATFORMS.transform_values { |value| driver_download_url(value) }
    end

    # Returns the gemspec files for the base gem.
    def self.base_files
      GEMSPEC.files
    end

    # Builds a gemspec for the given platform, adding the files currently in the native platform directory.
    def self.build_gemspec_for(platform)
      GEMSPEC.dup.tap do |s|
        s.platform = platform
        s.files += Dir["exe/#{platform}/**/*"]
      end
    end
  end
end
