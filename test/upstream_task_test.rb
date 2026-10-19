# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/upstream_task"

class UpstreamTaskTest < Minitest::Test
  GpgKeys = Tasks::Signatures::GpgKeys
  NpmKeys = Tasks::Signatures::NpmKeys

  class Updated < UpstreamTask
    attr_accessor :node_releases, :version_file
    attr_reader :lockfile_updates

    def initialize
      super
      @node_releases = []
      @lockfile_updates = 0
    end

    public :update_node, :next_patch_version

    private

    def read_https(url)
      raise ArgumentError, "Unexpected URL #{url}" unless url == NODE_RELEASES_URL

      JSON.generate(@node_releases)
    end

    def update_lockfile
      @lockfile_updates += 1
    end
  end

  class KeysUpdated < UpstreamTask
    attr_accessor :committed_node_keys, :pinned_node_keys, :committed_npm_keys, :pinned_npm_keys

    def initialize
      super
      @committed_node_keys = @pinned_node_keys = GpgKeys.new([])
      @committed_npm_keys = @pinned_npm_keys = NpmKeys.new([])
    end

    public :render_key_changes
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
    @keys_updated = KeysUpdated.new
    File.write @updated.version_file, VERSION_FILE
  end

  teardown do
    FileUtils.remove_entry @tmpdir
  end

  test "defines each update task and a pull request task for it" do
    Rake.with_application do
      UpstreamTask.create

      assert_equal ["update_keys"], Rake::Task["update_keys:pull_request"].prerequisites
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

  test "the key changes list the added, removed and changed keys" do
    @keys_updated.committed_node_keys = GpgKeys.new([gpg_key("AAAA", "Kept"), gpg_key("BBBB", "Retired")])
    @keys_updated.pinned_node_keys = GpgKeys.new([gpg_key("AAAA", "Kept"), gpg_key("CCCC", "New")])
    OpenSSL::PKey::EC.generate("prime256v1").then do |npm_key|
      @keys_updated.committed_npm_keys = NpmKeys.new([npm_key_entry(npm_key)])
      @keys_updated.pinned_npm_keys = NpmKeys.new([npm_key_entry(npm_key, "2027-01-01T00:00:00.000Z")])

      assert_equal <<~CHANGES.chomp, @keys_updated.render_key_changes
        - Removed Node.js release key `BBBB`: `Retired <retired@example.com>`
        - Added Node.js release key `CCCC`: `New <new@example.com>`
        - Changed npm registry key `#{NpmKeys.fingerprint(npm_key)}`: expires 2027-01-01
      CHANGES
    end
  end

  test "the key changes list a key whose subkeys changed under the same user id" do
    @keys_updated.committed_node_keys = GpgKeys.new([gpg_key("AAAA", "Kept")])
    @keys_updated.pinned_node_keys =
      GpgKeys.new([gpg_key("AAAA", "Kept", subkeys: [GpgKeys::Subkey.new(fingerprint: "BBBB", details:)])])

    assert_equal "- Changed Node.js release key `AAAA`: `Kept <kept@example.com>`", @keys_updated.render_key_changes
  end

  test "the key changes say when no key was added, removed or changed" do
    @keys_updated.committed_node_keys = @keys_updated.pinned_node_keys = GpgKeys.new([gpg_key("AAAA", "Kept")])

    assert_equal "No key was added, removed or changed in the details listed, but the key files differ, " \
                 "so check their diff.",
                 @keys_updated.render_key_changes
  end

  test "reads the committed npm keys from HEAD" do
    refute_empty UpstreamTask.new.send(:committed_npm_keys).keys
  end

  test "reads the committed node keys from HEAD" do
    skip "Git for Windows' gpg can't take a Windows path" if Gem.win_platform?
    skip "gpg not installed" unless system("gpg", "--version", out: File::NULL, err: File::NULL)

    refute_empty UpstreamTask.new.send(:committed_node_keys).keys
  end

  private

  def gpg_key(fingerprint, name, subkeys: [])
    uid = GpgKeys::Uid.new(name: "#{name} <#{name.downcase}@example.com>", status: nil)
    GpgKeys::Key.new(fingerprint:, uids: [uid], details:, subkeys:)
  end

  def npm_key_entry(key, expires = nil)
    { "keyid" => NpmKeys.fingerprint(key), "keytype" => "ecdsa-sha2-nistp256", "expires" => expires,
      "key" => [key.public_to_der].pack("m0") }
  end

  def details
    GpgKeys::Details.new(algorithm: "ed25519", capabilities: %w[sign certify], created: Time.utc(2025, 6, 28),
                         expires: nil, status: nil)
  end

  def patched_version
    @updated.next_patch_version(Gem::Version.new(Venetian::VERSION))
  end
end
