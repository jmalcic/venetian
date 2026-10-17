# frozen_string_literal: true

require "json"
require "openssl"
require "time"
require_relative "../../../lib/venetian/upstream"
require_relative "../helpers"

module Tasks
  module Signatures # :nodoc: all
    class NpmKeys
      class VerificationError < StandardError
      end

      include Helpers

      Key = Data.define(:key, :expires) do
        def self.parse(entry)
          new(key: OpenSSL::PKey.read(entry.fetch("key").unpack1("m")),
              expires: entry["expires"]&.then { |time| Time.iso8601(time) })
        end

        def verify(signature, message)
          key.verify("SHA256", signature.to_s.unpack1("m"), message)
        rescue OpenSSL::PKey::PKeyError
          false
        end
      end

      def self.parse(file)
        new(JSON.parse(file.read).fetch("keys"))
      end

      def initialize(keys)
        @keys = keys.to_h { |entry| [entry.fetch("keyid"), Key.parse(entry)] }
      end

      def verify(name, version, dist)
        Array(dist["signatures"]).any? do |signature|
          @keys[signature["keyid"]]&.then do |key|
            key.verify(signature["sig"], "#{name}@#{version}:#{dist["integrity"]}") &&
              (!key.expires || publish_time_for(name, version) < key.expires)
          end
        end
      end

      def verify!(name, version, dist)
        verify(name, version, dist) || raise(VerificationError)
      end

      private

      def publish_time_for(name, version)
        JSON.parse(read_https(Venetian::Upstream.npm_packument_url(name)))
            .dig("time", version)
            .tap { |time| raise "No publish time for #{name}@#{version}" unless time }
            .then { |time| Time.iso8601(time) }
      end
    end
  end
end
