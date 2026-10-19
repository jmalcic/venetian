# frozen_string_literal: true

require "json"
require "open3"
require "pathname"
require "tmpdir"
require_relative "../../lib/venetian/upstream"
require_relative "helpers"
require_relative "signatures/gpg_keys"
require_relative "signatures/npm_keys"

module Tasks
  module Signatures # :nodoc: all
    class VerificationError < StandardError
    end

    include Helpers

    KEYS_DIR = Pathname(__dir__).join("keys")
    NODE_KEYRING = KEYS_DIR.join("node.kbx")
    NPM_KEYS = KEYS_DIR.join("npm.json")

    NODE_KEYRING_URL = "https://github.com/nodejs/release-keys/raw/refs/heads/main/gpg-only-active-keys/pubring.kbx"
    NPM_KEYS_URL = "#{Venetian::Upstream::NPM_REGISTRY_URL}/-/npm/v1/keys".freeze

    def verify_checksum(source_url, pathname, verifier: nil, extractor: :itself, **)
      return super(source_url, pathname, extractor:, **) unless verifier

      super(source_url, pathname,
            extractor: ->(response) { verify_response(verifier, response, source_url) } >> extractor.to_proc, **)
    end

    private

    def verify_response(verifier, response, source_url)
      case verifier
      when :node then verify_node_signed_text(response)
      when :npm then verify_npm_metadata(response, source_url)
      else raise ArgumentError, "Unknown verifier #{verifier.inspect}"
      end
    end

    def verify_node_signed_text(clearsigned)
      gpgv node_keyring.to_path, clearsigned
    rescue VerificationError => e
      raise "Not signed by a pinned Node.js release key:\n#{e.message}"
    end

    def verify_npm_metadata(metadata, source_url)
      JSON.parse(metadata).tap do |package|
        name, version = package.values_at("name", "version")
        unless source_url == Venetian::Upstream.npm_metadata_url(name, version)
          raise "#{source_url} returned the metadata for #{name}@#{version}"
        end

        npm_keys.verify!(name, version, package.fetch("dist", {}))
      rescue NpmKeys::VerificationError
        raise "#{name}@#{version} isn't signed by a pinned npm registry key"
      end
    end

    def gpgv(keyring_path, clearsigned)
      requiring_gnupg "gpgv" do
        Open3.capture3("gpgv", "--keyring", keyring_path, "--output", "-", "-", stdin_data: clearsigned, binmode: true)
             .tap { |_response, error, status| raise VerificationError, error unless status.success? }
             .first
      end
    end

    def gpg_key_listing(keyring_path)
      Dir.mktmpdir do |home|
        requiring_gnupg "gpg" do
          Open3.capture3("gpg", "--homedir", home, "--no-options", "--no-default-keyring", "--keyring", keyring_path,
                         "--with-colons", "--with-subkey-fingerprint", "--list-keys")
               .tap { |_response, error, status| raise "Couldn't list the keys: #{error.strip}" unless status.success? }
               .first
               .force_encoding(Encoding::UTF_8)
               .scrub
        end
      end
    end

    def requiring_gnupg(command)
      yield
    rescue Errno::ENOENT
      raise "#{command} isn't installed: it comes with GnuPG"
    end

    def node_keyring
      NODE_KEYRING
    end

    def npm_keys
      @npm_keys ||= NpmKeys.parse(NPM_KEYS.read)
    end
  end
end
