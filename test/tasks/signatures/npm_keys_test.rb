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
          super([key_entry("current", current_key), key_entry("expiring", expiring_key, EXPIRES)])
        end

        private

        def key_entry(keyid, key, expires = nil)
          { "keyid" => keyid, "expires" => expires&.iso8601, "key" => [key.public_to_der].pack("m0") }
        end

        def read_https(url)
          raise ArgumentError, "Unexpected URL #{url}" unless url == Venetian::Upstream.npm_packument_url(NAME)

          JSON.generate({ "time" => publish_times.transform_values(&:iso8601) })
        end
      end

      setup do
        @keys = StubbedNpmKeys.new
      end

      test "verifies a signature from a pinned key" do
        assert @keys.verify(NAME, VERSION, dist(signature("current", @keys.current_key)))
      end

      test "rejects a signature from an unknown key" do
        refute @keys.verify(NAME, VERSION, dist(signature("unknown", @keys.current_key)))
      end

      test "rejects a signature attributed to another pinned key" do
        refute @keys.verify(NAME, VERSION, dist(signature("current", @keys.expiring_key)))
      end

      test "rejects a signature over another version" do
        refute @keys.verify(NAME, "1.62.0", dist(signature("current", @keys.current_key)))
      end

      test "rejects a signature over another integrity" do
        refute @keys.verify(NAME, VERSION, dist(signature("current", @keys.current_key), integrity: "sha512-other"))
      end

      test "rejects a malformed signature" do
        refute @keys.verify(NAME, VERSION, dist({ "keyid" => "current", "sig" => ["malformed"].pack("m0") }))
      end

      test "rejects metadata without signatures" do
        refute @keys.verify(NAME, VERSION, { "integrity" => INTEGRITY })
      end

      test "accepts any valid signature" do
        assert @keys.verify(NAME, VERSION,
                            dist(signature("unknown", @keys.current_key), signature("current", @keys.current_key)))
      end

      test "doesn't look up the publish time for a key without an expiry" do
        assert @keys.verify(NAME, VERSION, dist(signature("current", @keys.current_key)))
      end

      test "accepts an expired key for a version published before it expired" do
        @keys.publish_times = { VERSION => EXPIRES - 1 }

        assert @keys.verify(NAME, VERSION, dist(signature("expiring", @keys.expiring_key)))
      end

      test "rejects an expired key for a version published after it expired" do
        @keys.publish_times = { VERSION => EXPIRES }

        refute @keys.verify(NAME, VERSION, dist(signature("expiring", @keys.expiring_key)))
      end

      test "pinned keys parse" do
        assert_kind_of NpmKeys, NpmKeys.parse(NPM_KEYS)
      end

      private

      def signature(keyid, key, version: VERSION, integrity: INTEGRITY)
        { "keyid" => keyid, "sig" => [key.sign("SHA256", "#{NAME}@#{version}:#{integrity}")].pack("m0") }
      end

      def dist(*signatures, integrity: INTEGRITY)
        { "integrity" => integrity, "signatures" => signatures }
      end
    end
  end
end
