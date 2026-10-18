# frozen_string_literal: true

require "test_helper"
require_relative "../../rakelib/tasks/versioning"

module Tasks
  class VersioningTest < Minitest::Test
    class Versioned
      include Versioning

      attr_accessor :node_releases, :version_file, :gemspec_file

      def initialize
        @node_releases = []
      end

      def node_version
        latest_node_lts_version
      end

      public :patch_version_file, :patch_version_constants, :patch_gemspec, :next_patch_version

      private

      def read_https(url)
        raise ArgumentError, "Unexpected URL #{url}" unless url == NODE_RELEASES_URL
        raise OpenURI::HTTPError.new("503 Service Unavailable", StringIO.new) unless @node_releases

        JSON.generate(@node_releases)
      end
    end

    setup do
      @versioned = Versioned.new
      @tmpdir = Dir.mktmpdir
      @versioned.version_file = File.join(@tmpdir, "version.rb")
      FileUtils.cp Versioning::VERSION_FILE, @versioned.version_file
      @versioned.gemspec_file = File.join(@tmpdir, "venetian.gemspec")
      File.binwrite @versioned.gemspec_file,
                    File.binread(Versioning::GEMSPEC_FILE).sub(/(?<="playwright-ruby-client", )".+"/, '"~> 0.0.0"')

      assert_includes File.binread(@versioned.gemspec_file), '"playwright-ruby-client", "~> 0.0.0"'
    end

    teardown do
      FileUtils.remove_entry @tmpdir
    end

    test "latest node lts version is the first lts release without the v prefix" do
      @versioned.node_releases = [{ "version" => "v25.1.0", "lts" => false },
                                  { "version" => "v24.22.0", "lts" => "Krypton" },
                                  { "version" => "v22.20.0", "lts" => "Jod" }]

      assert_equal "24.22.0", @versioned.node_version
    end

    test "latest node lts version raises when there is no lts release" do
      @versioned.node_releases << { "version" => "v25.1.0", "lts" => false }

      assert_raises RuntimeError, match: /No LTS release found/ do
        @versioned.node_version
      end
    end

    test "patch version file for playwright bumps the gem and compatible playwright versions, not node" do
      @versioned.node_releases = nil
      @versioned.patch_version_file playwright: true

      File.read(@versioned.version_file).then do |contents|
        assert_includes contents, %(VERSION = "#{@versioned.next_patch_version(Gem::Version.new(Venetian::VERSION))}")
        assert_includes contents, %(COMPATIBLE_PLAYWRIGHT_VERSION = "#{Playwright::COMPATIBLE_PLAYWRIGHT_VERSION}")
        assert_includes contents, %(NODE_VERSION = "#{Venetian::NODE_VERSION}")
      end
    end

    test "patch version file for node bumps the gem and node versions, not the compatible playwright version" do
      @versioned.node_releases << { "version" => "v99.0.0", "lts" => "Future" }
      @versioned.patch_version_constants COMPATIBLE_PLAYWRIGHT_VERSION: "0.0.0"
      @versioned.patch_version_file node: true

      File.read(@versioned.version_file).then do |contents|
        assert_includes contents, %(VERSION = "#{@versioned.next_patch_version(Gem::Version.new(Venetian::VERSION))}")
        assert_includes contents, 'COMPATIBLE_PLAYWRIGHT_VERSION = "0.0.0"'
        assert_includes contents, 'NODE_VERSION = "99.0.0"'
      end
    end

    test "patch version file leaves the version file alone when the node releases can't be fetched" do
      @versioned.node_releases = nil

      assert_raises OpenURI::HTTPError do
        @versioned.patch_version_file node: true
      end
      assert_equal File.read(Versioning::VERSION_FILE), File.read(@versioned.version_file)
    end

    test "patch version constants rewrites both constants in the real version file" do
      @versioned.patch_version_constants VERSION: "9.8.7", COMPATIBLE_PLAYWRIGHT_VERSION: "6.5.4"

      assert_match Regexp.new('^  VERSION = "9\.8\.7"$'), File.read(@versioned.version_file)
      assert_match Regexp.new('^  COMPATIBLE_PLAYWRIGHT_VERSION = "6\.5\.4"$'), File.read(@versioned.version_file)
    end

    test "patch version constants writes backslashes literally" do
      @versioned.patch_version_constants VERSION: "a\\b"

      assert_includes File.read(@versioned.version_file), 'VERSION = "a\\\\b"'
    end

    test "patch version constants raises and leaves the file alone when a constant is missing" do
      assert_raises ArgumentError, match: /matches nothing/ do
        @versioned.patch_version_constants MISSING: "1.0.0"
      end
      assert_equal File.read(Versioning::VERSION_FILE), File.read(@versioned.version_file)
    end

    test "patch gemspec rewrites the playwright-ruby-client requirement in the real gemspec" do
      @versioned.patch_gemspec

      assert_match(/"playwright-ruby-client", "~> \d+\.\d+\.0"$/, File.binread(@versioned.gemspec_file))
      assert_includes File.binread(@versioned.gemspec_file), %("playwright-ruby-client", #{Versioning::CLIENT_REQUIREMENT}\n)
    end

    test "next patch version bumps the last segment" do
      assert_equal "1.2.4", @versioned.next_patch_version(Gem::Version.new("1.2.3"))
      assert_equal "0.3.10", @versioned.next_patch_version(Gem::Version.new("0.3.9"))
    end
  end
end
