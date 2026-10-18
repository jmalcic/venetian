# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/upstream_task"

class UpstreamTaskTest < Minitest::Test
  class Updated < UpstreamTask
    attr_accessor :node_releases, :version_file
    attr_reader :lockfile_updates

    def initialize
      super
      @node_releases = []
      @lockfile_updates = 0
    end

    public :update_node

    private

    def read_https(url)
      raise ArgumentError, "Unexpected URL #{url}" unless url == NODE_RELEASES_URL

      JSON.generate(@node_releases)
    end

    def update_lockfile
      @lockfile_updates += 1
    end
  end

  VERSION_FILE = <<~RUBY.freeze
    module Venetian
      VERSION = "#{Venetian::VERSION}"
      COMPATIBLE_PLAYWRIGHT_VERSION = "0.0.0"
      NODE_VERSION = "#{Venetian::NODE_VERSION}"
    end
  RUBY

  setup do
    @updated = Updated.new
    @tmpdir = Dir.mktmpdir
    @updated.version_file = File.join(@tmpdir, "version.rb")
    File.write @updated.version_file, VERSION_FILE
  end

  teardown do
    FileUtils.remove_entry @tmpdir
  end

  test "defines update node and a pull request task for it" do
    Rake.with_application do
      UpstreamTask.create

      assert_equal ["update_node"], Rake::Task["update_node:pull_request"].prerequisites
    end
  end

  test "update node patches the node version and bumps the gem version for a later lts release" do
    @updated.node_releases << { "version" => "v99.0.0", "lts" => "Future" }
    @updated.update_node

    assert_equal VERSION_FILE.sub(/(?<=VERSION = ")#{Regexp.escape(Venetian::VERSION)}/, patched_version)
                             .sub(Venetian::NODE_VERSION, "99.0.0"),
                 File.read(@updated.version_file)
    assert_equal 1, @updated.lockfile_updates
  end

  test "update node leaves the compatible playwright version alone" do
    @updated.node_releases << { "version" => "v99.0.0", "lts" => "Future" }
    @updated.update_node

    assert_includes File.read(@updated.version_file), 'COMPATIBLE_PLAYWRIGHT_VERSION = "0.0.0"'
  end

  test "update node leaves the version file alone when the bundled node is the latest lts release" do
    @updated.node_releases << { "version" => "v#{Venetian::NODE_VERSION}", "lts" => "Krypton" }
    @updated.update_node

    assert_equal VERSION_FILE, File.read(@updated.version_file)
    assert_equal 0, @updated.lockfile_updates
  end

  private

  def patched_version
    Gem::Version.new(Venetian::VERSION).segments.then { |segments| [*segments[0..-2], segments.last.succ].join(".") }
  end
end
