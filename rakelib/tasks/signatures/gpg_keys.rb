# frozen_string_literal: true

require_relative "key_changes"

module Tasks
  module Signatures # :nodoc: all
    class GpgKeys
      include KeyChanges

      ALGORITHMS = { "1" => "rsa", "16" => "elg", "17" => "dsa" }.freeze
      CAPABILITIES = { "s" => "sign", "c" => "certify", "e" => "encrypt", "a" => "authenticate" }.freeze
      STATUSES = { "r" => "revoked", "e" => "expired", "i" => "invalid", "d" => "disabled" }.freeze
      module Sanitization
        class << self
          def unescape(text)
            text.b
                .gsub(/\\(x\h\h|.)/n) { CHARACTERS.fetch(Regexp.last_match(1)) { |escaped| byte(escaped) } }
                .force_encoding(Encoding::UTF_8)
                .scrub
          end

          def code(text)
            return "(empty)" if text.empty?

            if (length = fence_length(text).nonzero?) || padded?(text)
              "`#{"`" * length.to_i} #{visible_characters(text)} #{"`" * length.to_i}`"
            else
              "`#{visible_characters(text)}`"
            end
          end

          private

          def visible_characters(text)
            text.gsub(HIDDEN) { |character| character.dump[1..-2] }
          end

          def padded?(text)
            text.match?(/[^ ]/) && (text.start_with?(" ") || text.end_with?(" "))
          end

          def fence_length(text)
            text.scan(/`+/).collect(&:size).max.to_i
          end

          def byte(escaped)
            escaped.match?(/\Ax\h\h\z/) ? [escaped[1..].hex].pack("C") : escaped
          end
        end

        HIDDEN = /[\\[:cntrl:]\p{Cf}\p{Zl}\p{Zp}\p{Default_Ignorable_Code_Point}\u2800[\p{Zs}&&[^ ]]]/
        CHARACTERS = { "n" => "\n", "r" => "\r", "t" => "\t", "f" => "\f", "v" => "\v", "b" => "\b",
                       "0" => "\0" }.freeze
      end

      Details = Data.define(:algorithm, :capabilities, :created, :expires, :status) do
        def self.parse(fields)
          new(algorithm: algorithm(fields),
              capabilities: fields[11].to_s.chars.filter_map { |cap| CAPABILITIES[cap] },
              created: time(fields[5]),
              expires: time(fields[6]),
              status: STATUSES[fields[1]])
        end

        def self.algorithm(fields)
          fields[16].to_s.empty? ? "#{ALGORITHMS.fetch(fields[3], "algorithm #{fields[3]} ")}#{fields[2]}" : fields[16]
        end

        def self.time(timestamp)
          Time.at(Integer(timestamp)).utc unless timestamp.to_s.empty?
        end

        def to_s
          [algorithm, *capabilities_description, "created #{date(created)}", expires_description, *status].join(", ")
        end

        private

        def date(time)
          time.strftime("%Y-%m-%d")
        end

        def capabilities_description
          capabilities.join(" and ") unless capabilities.empty?
        end

        def expires_description
          expires ? "expires #{date(expires)}" : "doesn't expire"
        end
      end

      Subkey = Data.define(:fingerprint, :details) do
        def to_s
          "Subkey `#{fingerprint}`: #{details}"
        end
      end

      Uid = Data.define(:name, :status) do
        def self.parse(fields)
          new(name: Sanitization.unescape(fields[9]), status: STATUSES[fields[1]])
        end

        def to_s
          [Sanitization.code(name), *("(#{status})" if status)].join(" ")
        end
      end

      Key = Data.define(:fingerprint, :uids, :details, :subkeys) do
        def self.parse(records)
          new(fingerprint: records[1]&.then { |fields| fields[9] if fields.first == "fpr" },
              uids: records.select { |fields| fields.first == "uid" }
                           .collect { |fields| Uid.parse(fields) },
              details: Details.parse(records.first),
              subkeys: subkeys(records))
        end

        def self.subkeys(records)
          records.each_cons(2)
                 .select { |sub, fpr| sub.first == "sub" && fpr.first == "fpr" }
                 .collect { |sub, fpr| Subkey.new(fingerprint: fpr[9], details: Details.parse(sub)) }
        end

        def initialize(...)
          super
          raise "gpg listed a key without a fingerprint" if fingerprint.nil?
        end

        def id
          fingerprint
        end

        def uid
          uids.first&.name
        end

        def to_s
          uids.first&.to_s || "(no user ID)"
        end

        def lines
          [*uids.drop(1).collect { |other| "Also #{other}" }, details.to_s, *subkeys.collect(&:to_s)]
        end
      end

      def self.parse(listing)
        new(listing.lines
                   .collect { |line| line.split(":") }
                   .slice_before { |fields| fields.first == "pub" }
                   .select { |records| records.first.first == "pub" }
                   .collect { |records| Key.parse(records) })
      end

      attr_reader :keys

      def initialize(keys)
        @keys = keys
        super()
      end

      def key_kind
        "Node.js release key"
      end

      def to_s
        keys.collect { |key| ["- `#{key.fingerprint}`: #{key}", *key.lines.collect { |line| "  - #{line}" }] }
            .join("\n")
      end
    end
  end
end
