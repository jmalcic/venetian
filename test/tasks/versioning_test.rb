# frozen_string_literal: true

require "test_helper"
require_relative "../../rakelib/tasks/versioning"

module Tasks
  class VersioningTest < Minitest::Test
    class Versioned
      include Versioning

      attr_accessor :version_file, :gemspec_file

      public :patch_version_constants, :patch_gemspec, :next_patch_version
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

    test "patch version constants rewrites both constants in the real version file" do
      @versioned.patch_version_constants VERSION: "9.8.7", COMPATIBLE_PLAYWRIGHT_VERSION: "6.5.4"

      assert_match Regexp.new('^  VERSION = "9\.8\.7"$'), File.read(@versioned.version_file)
      assert_match Regexp.new('^  COMPATIBLE_PLAYWRIGHT_VERSION = "6\.5\.4"$'), File.read(@versioned.version_file)
    end

    test "patch version constants writes backslashes literally" do
      @versioned.patch_version_constants VERSION: "a\\b"

      assert_includes File.read(@versioned.version_file), 'VERSION = "a\\\\b"'
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
