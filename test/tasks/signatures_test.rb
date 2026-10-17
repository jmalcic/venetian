# frozen_string_literal: true

require "test_helper"
require_relative "../../rakelib/tasks/signatures"

module Tasks
  class SignaturesTest < Minitest::Test
    NAME = "playwright-core"
    VERSION = "1.63.0"
    INTEGRITY = "sha512-#{["integrity"].pack("m0")}".freeze
    EXPIRES = Time.utc(2025, 1, 29)

    METADATA_URL = Venetian::Upstream.npm_metadata_url(NAME, VERSION)
    CHECKSUMS = "abc123  node.tar.gz\n"
    CHECKSUMS_URL = "https://example.com/SHASUMS256.txt.asc"

    class StubbedNpmKeys < Signatures::NpmKeys
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

    class TemporaryKeyring
      class << self
        def with_key(&)
          raise GpgNotInstalled unless exists?

          Dir.mktmpdir do |home|
            new(home).generate_keyring(&)
          end
        end

        private

        def exists?
          system "gpg", "--version", out: File::NULL, err: File::NULL
        end
      end

      class GpgNotInstalled < StandardError
      end

      attr_reader :path

      def initialize(home, path: Pathname(home).join("keyring.gpg"))
        @home = home
        @path = path
      end

      def generate_keyring
        quick_gen_key
        export
        yield self
      ensure
        kill_agent
      end

      def clearsign(text)
        Open3.capture2(*command, "--clearsign", stdin_data: text).first
      end

      private

      attr_reader :home

      def quick_gen_key
        Open3.capture2e(*command, "--quick-gen-key", "Test <test@example.com>", "ed25519", "sign", "never")
             .then { |output, status| raise "gpg --quick-gen-key failed:\n#{output}" unless status.success? }
      end

      def export
        system(*command, "--output", path.to_path, "--export", exception: true)
      end

      def command
        ["gpg", "--homedir", home, "--batch", "--pinentry-mode", "loopback", "--passphrase", ""]
      end

      def kill_agent
        system "gpgconf", "--homedir", home, "--kill", "gpg-agent", out: File::NULL, err: File::NULL
      end
    end

    class Verified
      include Signatures

      attr_accessor :node_keyring, :npm_keys, :responses

      def node_signed_text(clearsigned)
        verify_node_signed_text clearsigned
      end

      def npm_metadata(metadata, source_url = METADATA_URL)
        verify_npm_metadata metadata, source_url
      end

      private

      def read_https(url)
        responses.fetch(url)
      end
    end

    module Signing
      private

      def download_digest
        Digest::SHA512.file(@download).hexdigest
      end

      def signature(keyid, key)
        { "keyid" => keyid, "sig" => [key.sign("SHA256", "#{NAME}@#{VERSION}:#{INTEGRITY}")].pack("m0") }
      end

      def metadata(*signatures, version: VERSION)
        JSON.generate({ "name" => NAME, "version" => version,
                        "dist" => { "integrity" => INTEGRITY, "signatures" => signatures } })
      end

      def with_gpg_key(&)
        skip "Git for Windows' gpg can't take a Windows path as its home directory" if Gem.win_platform?

        TemporaryKeyring.with_key(&)
      rescue TemporaryKeyring::GpgNotInstalled
        skip "gpg not installed"
      end
    end

    module NpmMetadata
      module Tests
        extend ActiveSupport::Concern

        included do
          test "npm metadata is returned when signed by a pinned key" do
            metadata(signature("current", @npm_keys.current_key)).then do |metadata|
              assert_equal JSON.parse(metadata), @verified.npm_metadata(metadata)
            end
          end

          test "npm metadata checks an expired key against the publish time" do
            @npm_keys.publish_times = { VERSION => EXPIRES - 1 }

            assert_equal NAME,
                         @verified.npm_metadata(metadata(signature("expiring", @npm_keys.expiring_key))).fetch("name")
          end

          test "npm metadata raises when an expired key signed a version published after it expired" do
            @npm_keys.publish_times = { VERSION => EXPIRES }

            assert_raises RuntimeError, match: /#{NAME}@#{VERSION} isn't signed by a pinned npm registry key/ do
              @verified.npm_metadata metadata(signature("expiring", @npm_keys.expiring_key))
            end
          end

          test "npm metadata raises when there's no publish time to check an expired key against" do
            assert_raises RuntimeError, match: /No publish time for #{NAME}@#{VERSION}/ do
              @verified.npm_metadata metadata(signature("expiring", @npm_keys.expiring_key))
            end
          end

          test "npm metadata raises when unsigned" do
            assert_raises RuntimeError, match: /#{NAME}@#{VERSION} isn't signed by a pinned npm registry key/ do
              @verified.npm_metadata JSON.generate({ "name" => NAME, "version" => VERSION, "dist" => {} })
            end
          end

          test "npm metadata raises when signed by an unknown key" do
            assert_raises RuntimeError, match: /isn't signed by a pinned npm registry key/ do
              @verified.npm_metadata metadata(signature("unknown", @npm_keys.current_key))
            end
          end

          test "npm metadata raises when it describes a package other than the one requested" do
            assert_raises RuntimeError, match: /#{METADATA_URL} returned the metadata for #{NAME}@1.62.0/ do
              @verified.npm_metadata metadata(signature("current", @npm_keys.current_key), version: "1.62.0")
            end
          end
        end
      end
    end

    module NodeSignedText
      module Tests
        extend ActiveSupport::Concern

        included do
          test "node signed text returns the signed text when signed by a pinned key" do
            with_gpg_key do |keyring|
              @verified.node_keyring = keyring.path

              assert_equal CHECKSUMS, @verified.node_signed_text(keyring.clearsign(CHECKSUMS))
            end
          end

          test "node signed text raises when the signed text was changed" do
            with_gpg_key do |keyring|
              @verified.node_keyring = keyring.path

              assert_raises RuntimeError, match: /Not signed by a pinned Node.js release key/ do
                @verified.node_signed_text keyring.clearsign(CHECKSUMS).sub("abc123", "def456")
              end
            end
          end

          test "node signed text raises when signed by an unknown key" do
            with_gpg_key do |keyring|
              with_gpg_key do |other_keyring|
                @verified.node_keyring = other_keyring.path

                assert_raises RuntimeError, match: /Not signed by a pinned Node.js release key/ do
                  @verified.node_signed_text keyring.clearsign(CHECKSUMS)
                end
              end
            end
          end

          test "node signed text raises when unsigned" do
            with_gpg_key do |keyring|
              @verified.node_keyring = keyring.path

              assert_raises RuntimeError, match: /Not signed by a pinned Node.js release key/ do
                @verified.node_signed_text CHECKSUMS
              end
            end
          end
        end
      end
    end

    module VerifyChecksum
      module Tests
        extend ActiveSupport::Concern

        included do
          test "verify checksum extracts the checksum from the raw response without a verifier" do
            @verified.responses = { CHECKSUMS_URL => download_digest }

            assert_equal download_digest, @verified.verify_checksum(CHECKSUMS_URL, @download)
          end

          test "verify checksum extracts the checksum from the npm metadata once its signature is verified" do
            metadata(signature("current", @npm_keys.current_key)).then do |metadata|
              @verified.responses = { METADATA_URL => metadata }

              assert_equal download_digest,
                           @verified.verify_checksum(METADATA_URL, @download,
                                                     verifier: :npm,
                                                     extractor: { JSON.parse(metadata) => download_digest })
            end
          end

          test "verify checksum raises before extracting the checksum when the npm metadata isn't signed" do
            @verified.responses = { METADATA_URL => metadata }

            assert_raises RuntimeError, match: /isn't signed by a pinned npm registry key/ do
              @verified.verify_checksum METADATA_URL, @download,
                                        verifier: :npm, extractor: ->(_) { flunk "Extracted a checksum" }
            end
          end

          test "verify checksum extracts the checksum from the node checksums once their signature is verified" do
            with_gpg_key do |keyring|
              @verified.node_keyring = keyring.path
              @verified.responses = { CHECKSUMS_URL => keyring.clearsign("#{download_digest}  download\n") }

              assert_equal download_digest,
                           @verified.verify_checksum(CHECKSUMS_URL, @download,
                                                     verifier: :node,
                                                     extractor: ->(checksums) { checksums[/\A(\h+)  download$/, 1] })
            end
          end

          test "verify checksum raises before extracting the checksum when the node checksums aren't signed" do
            with_gpg_key do |keyring|
              @verified.node_keyring = keyring.path
              @verified.responses = { CHECKSUMS_URL => "#{download_digest}  download\n" }

              assert_raises RuntimeError, match: /Not signed by a pinned Node.js release key/ do
                @verified.verify_checksum CHECKSUMS_URL, @download,
                                          verifier: :node, extractor: ->(_) { flunk "Extracted a checksum" }
              end
            end
          end
        end
      end
    end

    include Signing
    include NpmMetadata::Tests
    include NodeSignedText::Tests
    include VerifyChecksum::Tests

    setup do
      @verified = Verified.new
      @npm_keys = StubbedNpmKeys.new
      @verified.npm_keys = @npm_keys
      @tmpdir = Dir.mktmpdir
      @download = Pathname(@tmpdir).join("download")
      @download.binwrite "contents"
    end

    teardown do
      FileUtils.remove_entry @tmpdir
    end
  end
end
