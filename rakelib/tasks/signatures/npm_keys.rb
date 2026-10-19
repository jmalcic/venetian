# frozen_string_literal: true

require "digest"
require "json"
require "openssl"
require "time"
require_relative "../../../lib/venetian/upstream"
require_relative "../helpers"
require_relative "key_changes"

module Tasks
  module Signatures # :nodoc: all
    class NpmKeys
      class VerificationError < StandardError
      end

      include KeyChanges

      Key = Data.define(:keyid, :key, :expires) do
        include Helpers

        def self.parse(entry)
          raise "Unsupported npm key type #{entry["keytype"]}" unless entry["keytype"] == "ecdsa-sha2-nistp256"

          new(keyid: entry.fetch("keyid"), key: OpenSSL::PKey.read(entry.fetch("key").unpack1("m")),
              expires: entry["expires"]&.then { |time| Time.iso8601(time) })
            .tap(&:validate!)
        end

        def validate!
          raise "#{keyid} isn't a P-256 ECDSA key" unless p256?
          raise "#{keyid} isn't the fingerprint of its key" unless keyid == fingerprint
        end

        def p256?
          key.is_a?(OpenSSL::PKey::EC) && key.group.curve_name == "prime256v1"
        end

        def fingerprint
          NpmKeys.fingerprint(key)
        end

        def id
          keyid
        end

        def verifies?(signature, name, version, integrity)
          verify(signature["sig"], "#{name}@#{version}:#{integrity}") &&
            (!expires || publish_time_for(name, version) < expires)
        end

        def to_s
          expires ? "expires #{expires.getutc.strftime("%Y-%m-%d")}" : "doesn't expire"
        end

        def ==(other)
          other.is_a?(Key) && keyid == other.keyid && der == other.der && expires == other.expires
        end
        alias_method :eql?, :==

        def hash
          [keyid, der, expires].hash
        end

        protected

        def der
          key.public_to_der
        end

        private

        def verify(sig, message)
          key.verify("SHA256", sig.to_s.unpack1("m"), message)
        rescue OpenSSL::PKey::PKeyError
          false
        end

        def publish_time_for(name, version)
          JSON.parse(read_https(Venetian::Upstream.npm_packument_url(name)))
              .dig("time", version)
              .tap { |time| raise "No publish time for #{name}@#{version}" unless time }
              .then { |time| Time.iso8601(time) }
        end
      end

      def self.fingerprint(key)
        ["ecdsa-sha2-nistp256", "nistp256", key.public_key.to_octet_string(:uncompressed)]
          .collect { |part| [part.bytesize].pack("N") + part }
          .join
          .then { |ssh_public_key| "SHA256:#{[Digest::SHA256.digest(ssh_public_key)].pack("m0").delete("=")}" }
      end

      def self.parse(json)
        new(JSON.parse(json).fetch("keys"))
      end

      attr_reader :keys

      def initialize(entries)
        @keys = entries.map { |entry| Key.parse(entry) }
        super()
      end

      def verify(name, version, dist)
        Array(dist["signatures"]).any? do |signature|
          keys.find { |key| key.keyid == signature["keyid"] }
              &.verifies?(signature, name, version, dist["integrity"])
        end
      end

      def verify!(name, version, dist)
        verify(name, version, dist) || raise(VerificationError)
      end

      def key_kind
        "npm registry key"
      end
    end
  end
end
