# frozen_string_literal: true

require "playwright"

module Venetian
  # # \Upstream
  #
  # Provides platform mappings and URLs for Playwright.
  module Upstream
    # Describes how to assemble the Playwright driver for a single gem platform.
    #
    # +node_dir+:: the platform infix used in Node.js release archive names (e.g. "linux-x64")
    # +windows+:: whether this platform's Node.js archive is a Windows build (.zip, node.exe)
    PlatformInfo = Data.define(:node_dir, :windows) do
      # Returns the filename of the Node executable inside the assembled driver.
      def executable_name
        windows ? "node.exe" : "node"
      end

      # Returns the file extension of the Node.js release archive for this platform.
      def node_archive_extension
        windows ? "zip" : "tar.gz"
      end

      # Returns the URL to download the Node.js release archive for the given version.
      def node_url_for(version)
        "#{NODE_DIST_URL}/v#{version}/node-v#{version}-#{node_dir}.#{node_archive_extension}"
      end
    end

    # map of gem platform strings to Node.js release info
    NATIVE_PLATFORMS = { "x86_64-linux" => PlatformInfo.new(node_dir: "linux-x64", windows: false),
                         "aarch64-linux" => PlatformInfo.new(node_dir: "linux-arm64", windows: false),
                         "x86_64-darwin" => PlatformInfo.new(node_dir: "darwin-x64", windows: false),
                         "arm64-darwin" => PlatformInfo.new(node_dir: "darwin-arm64", windows: false),
                         "x64-mingw-ucrt" => PlatformInfo.new(node_dir: "win-x64", windows: true) }.freeze

    # base for the npm registry, source of the playwright-core package
    NPM_REGISTRY_URL = "https://registry.npmjs.org"

    # base for Node.js release downloads
    NODE_DIST_URL = "https://nodejs.org/dist"

    # Returns the URL to download the playwright-core npm package containing the driver's JS sources.
    def self.playwright_core_url
      "#{NPM_REGISTRY_URL}/playwright-core/-/playwright-core-#{Playwright::COMPATIBLE_PLAYWRIGHT_VERSION}.tgz"
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
