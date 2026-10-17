# frozen_string_literal: true

require "test_helper"
require_relative "../../rakelib/tasks/versioning"

module Tasks
  class VersioningTest < Minitest::Test
    class Versioned
      include Versioning

      attr_accessor :version_file

      public :patch_version_file
    end

    VERSION_FILE = <<~RUBY.freeze
      module Venetian
        VERSION = "#{Venetian::VERSION}"
        COMPATIBLE_PLAYWRIGHT_VERSION = "0.0.0"
      end
    RUBY

    setup do
      @versioned = Versioned.new
      @tmpdir = Dir.mktmpdir
      @versioned.version_file = File.join(@tmpdir, "version.rb")
      File.write @versioned.version_file, VERSION_FILE
    end

    teardown do
      FileUtils.remove_entry @tmpdir
    end

    test "patch version file bumps the gem version and patches the compatible playwright version" do
      @versioned.patch_version_file

      assert_equal VERSION_FILE.sub(/(?<=VERSION = ")#{Regexp.escape(Venetian::VERSION)}/, patched_version)
                               .sub("0.0.0", Playwright::COMPATIBLE_PLAYWRIGHT_VERSION),
                   File.read(@versioned.version_file)
    end

    private

    def patched_version
      Gem::Version.new(Venetian::VERSION).segments.then { |segments| [*segments[0..-2], segments.last.succ].join(".") }
    end
  end
end
