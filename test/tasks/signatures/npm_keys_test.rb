# frozen_string_literal: true

require "test_helper"
require_relative "../../../rakelib/tasks/signatures"

module Tasks
  module Signatures
    class NpmKeysTest < Minitest::Test
      NAME = "playwright-core"
      VERSION = "1.63.0"
      INTEGRITY = "sha512-#{["integrity"].pack("m0")}".freeze
      EXPIRES = Time.utc(2025, 1, 29)

      class StubbedNpmKeys < NpmKeys
        attr_reader :current_key, :expiring_key
        attr_accessor :publish_times

        def initialize
          @current_key = OpenSSL::PKey::EC.generate("prime256v1")
          @expiring_key = OpenSSL::PKey::EC.generate("prime256v1")
          @publish_times = {}
          super([key_entry(current_key), key_entry(expiring_key, EXPIRES)])
        end

        def verify(...)
          OpenURI.stub :open_uri, ->(uri, *args, &block) { respond_to_uri(uri, *args, &block) } do
            super
          end
        end

        private

        def key_entry(key, expires = nil)
          { "keyid" => NpmKeys.fingerprint(key), "keytype" => "ecdsa-sha2-nistp256",
            "expires" => expires&.iso8601, "key" => [key.public_to_der].pack("m0") }
        end

        def respond_to_uri(uri, *, &)
          raise ArgumentError, "Unexpected URL #{uri}" unless uri.to_s == Venetian::Upstream.npm_packument_url(NAME)

          StringIO.new(JSON.generate({ "time" => publish_times.transform_values(&:iso8601) })).then(&)
        end
      end

      setup do
        @keys = StubbedNpmKeys.new
        @entry = { "keyid" => NpmKeys.fingerprint(@keys.current_key), "keytype" => "ecdsa-sha2-nistp256",
                   "expires" => nil, "key" => [@keys.current_key.public_to_der].pack("m0") }
      end

      test "verifies a signature from a pinned key" do
        assert @keys.verify(NAME, VERSION, dist(signature(@keys.current_key)))
      end

      test "rejects a signature from an unknown key" do
        refute @keys.verify(NAME, VERSION, dist(signature(@keys.current_key, keyid: "SHA256:unknown")))
      end

      test "rejects a signature attributed to another pinned key" do
        refute @keys.verify(NAME, VERSION,
                            dist(signature(@keys.expiring_key, keyid: NpmKeys.fingerprint(@keys.current_key))))
      end

      test "rejects a signature over another version" do
        refute @keys.verify(NAME, "1.62.0", dist(signature(@keys.current_key)))
      end

      test "rejects a signature over another integrity" do
        refute @keys.verify(NAME, VERSION, dist(signature(@keys.current_key), integrity: "sha512-other"))
      end

      test "rejects a malformed signature" do
        refute @keys.verify(NAME, VERSION,
                            dist({ "keyid" => NpmKeys.fingerprint(@keys.current_key),
                                   "sig" => ["malformed"].pack("m0") }))
      end

      test "rejects metadata without signatures" do
        refute @keys.verify(NAME, VERSION, { "integrity" => INTEGRITY })
      end

      test "accepts any valid signature" do
        assert @keys.verify(NAME, VERSION,
                            dist(signature(@keys.current_key, keyid: "SHA256:unknown"), signature(@keys.current_key)))
      end

      test "doesn't look up the publish time for a key without an expiry" do
        assert @keys.verify(NAME, VERSION, dist(signature(@keys.current_key)))
      end

      test "accepts an expired key for a version published before it expired" do
        @keys.publish_times = { VERSION => EXPIRES - 1 }

        assert @keys.verify(NAME, VERSION, dist(signature(@keys.expiring_key)))
      end

      test "rejects an expired key for a version published after it expired" do
        @keys.publish_times = { VERSION => EXPIRES }

        refute @keys.verify(NAME, VERSION, dist(signature(@keys.expiring_key)))
      end

      test "describes a key by its expiry" do
        assert_equal "expires 2025-01-29",
                     NpmKeys::Key.new(keyid: "expiring", key: @keys.expiring_key, expires: EXPIRES).to_s
        assert_equal "doesn't expire", NpmKeys::Key.new(keyid: "current", key: @keys.current_key, expires: nil).to_s
      end

      test "keys parsed from the same entry are equal" do
        assert_equal NpmKeys::Key.parse(@entry), NpmKeys::Key.parse(@entry)
        assert_equal NpmKeys::Key.parse(@entry).hash, NpmKeys::Key.parse(@entry).hash
      end

      test "keys differing in their key id, key or expiry aren't equal" do
        refute_equal NpmKeys::Key.new(keyid: "current", key: @keys.current_key, expires: nil),
                     NpmKeys::Key.new(keyid: "other", key: @keys.current_key, expires: nil)
        refute_equal NpmKeys::Key.new(keyid: "current", key: @keys.current_key, expires: nil),
                     NpmKeys::Key.new(keyid: "current", key: @keys.expiring_key, expires: nil)
        refute_equal NpmKeys::Key.new(keyid: "current", key: @keys.current_key, expires: nil),
                     NpmKeys::Key.new(keyid: "current", key: @keys.current_key, expires: EXPIRES)
      end

      test "rejects a key of a type it can't fingerprint" do
        assert_raises RuntimeError, match: /Unsupported npm key type ecdsa-sha2-nistp384/ do
          NpmKeys::Key.parse(@entry.merge("keytype" => "ecdsa-sha2-nistp384"))
        end
      end

      test "rejects a key that isn't a p-256 ecdsa key" do
        assert_raises RuntimeError, match: /SHA256:rsa isn't a P-256 ECDSA key/ do
          NpmKeys::Key.parse(@entry.merge("keyid" => "SHA256:rsa",
                                          "key" => [OpenSSL::PKey::RSA.generate(2048).public_to_der].pack("m0")))
        end
      end

      test "rejects key ids listed more than once" do
        assert_raises RuntimeError, match: /Duplicate npm registry key IDs #{Regexp.escape(@entry["keyid"])}/ do
          NpmKeys.new([@entry, @entry])
        end
      end

      test "rejects a key whose id isn't its key's fingerprint" do
        assert_raises RuntimeError, match: /SHA256:other isn't the fingerprint of its key/ do
          NpmKeys::Key.parse(@entry.merge("keyid" => "SHA256:other"))
        end
      end

      test "pinned keys parse" do
        assert_kind_of NpmKeys, NpmKeys.parse(NPM_KEYS.read)
      end

      private

      def signature(key, keyid: NpmKeys.fingerprint(key), version: VERSION, integrity: INTEGRITY)
        { "keyid" => keyid, "sig" => [key.sign("SHA256", "#{NAME}@#{version}:#{integrity}")].pack("m0") }
      end

      def dist(*signatures, integrity: INTEGRITY)
        { "integrity" => integrity, "signatures" => signatures }
      end
    end
  end
end
