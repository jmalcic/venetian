# frozen_string_literal: true

require "test_helper"
require "digest"

module Venetian
  class UpstreamTest < Minitest::Test
    test "playwright core url uses the advertised Playwright version" do
      assert_match COMPATIBLE_PLAYWRIGHT_VERSION, Upstream.playwright_core_url
    end

    test "playwright core metadata url uses the advertised Playwright version" do
      assert_match COMPATIBLE_PLAYWRIGHT_VERSION, Upstream.playwright_core_metadata_url
    end

    test "node checksums url is alongside the node url" do
      assert_equal File.dirname(Upstream::NATIVE_PLATFORMS.fetch("x64-mingw-ucrt").node_url_for(NODE_VERSION)),
                   File.dirname(Upstream::NATIVE_PLATFORMS.fetch("x64-mingw-ucrt").node_checksums_url_for(NODE_VERSION))
    end

    test "node checksum pattern captures the checksum of the downloaded archive only" do
      Upstream::NATIVE_PLATFORMS.each_value do |platform_info|
        archive_name = File.basename(platform_info.node_url_for(NODE_VERSION))

        assert_equal fake_checksum_for(archive_name),
                     node_checksums[platform_info.node_checksum_pattern_for(NODE_VERSION), 1],
                     "for #{archive_name}"
      end
    end

    test "client dependency allows later patches of the advertised Playwright minor version" do
      assert client_requirement.satisfied_by?(Gem::Version.new("#{major}.#{minor}.9"))
    end

    test "client dependency excludes the next Playwright minor version" do
      refute client_requirement.satisfied_by?(Gem::Version.new("#{major}.#{minor.succ}.0"))
    end

    test "client dependency excludes the next Playwright major version" do
      refute client_requirement.satisfied_by?(Gem::Version.new("#{major.succ}.0.0"))
    end

    private

    def node_checksums
      %w[darwin-arm64 darwin-x64 linux-arm64 linux-x64 linux-x64-musl win-arm64 win-x64]
        .product(%w[tar.gz tar.xz zip 7z])
        .collect { |(dir, ext)| "node-v#{NODE_VERSION}-#{dir}.#{ext}" }
        .collect_concat { |name| ["#{name}.sig", "win-x64/#{name}", name] }
        .collect { |name| "#{fake_checksum_for(name)}  #{name}\n" }
        .join
    end

    def fake_checksum_for(name)
      Digest::SHA256.hexdigest(name)
    end

    def client_requirement
      Gem.loaded_specs
         .fetch("venetian")
         .dependencies
         .detect { |dependency| dependency.name == "playwright-ruby-client" }
         .requirement
    end

    def major
      Gem::Version.new(COMPATIBLE_PLAYWRIGHT_VERSION).segments[0]
    end

    def minor
      Gem::Version.new(COMPATIBLE_PLAYWRIGHT_VERSION).segments[1]
    end
  end
end
