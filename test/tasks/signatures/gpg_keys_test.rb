# frozen_string_literal: true

require "test_helper"
require_relative "../../../rakelib/tasks/signatures"

module Tasks
  module Signatures
    class GpgKeysTest < Minitest::Test
      ADA = "1A2B3C4D5E6F7A8B9C0D1E2F3A4B5C6D7E8F9A0B"
      ADA_SUBKEY = "0F1E2D3C4B5A69788796A5B4C3D2E1F00F1E2D3C"
      ZOE = "2B3C4D5E6F7A8B9C0D1E2F3A4B5C6D7E8F9A0B1C"
      RETIRED = "0123456789ABCDEF0123456789ABCDEF01234567"

      LISTING = <<~'COLONS'
        tru::1:1783362189:0:3:1:5
        pub:-:255:22:9C0D1E2F3A4B5C6D7E8F9A0B:1751136988:::-:::scESC:::::ed25519:::0:
        fpr:::::::::1A2B3C4D5E6F7A8B9C0D1E2F3A4B5C6D7E8F9A0B:
        uid:-::::1773151025::0123::Ada Example <ada@example.com>::::::::::0:
        uid:-::::1751136988::4567::Ada Example <ada@example.org>::::::::::0:
        sub:-:255:18:96A5B4C3D2E1F00F1E2D3C:1751136988::::::e:::::cv25519::
        fpr:::::::::0F1E2D3C4B5A69788796A5B4C3D2E1F00F1E2D3C:
        pub:-:255:22:0D1E2F3A4B5C6D7E8F9A0B1C:1677815220:::-:::scESC:::::ed25519:::0:
        fpr:::::::::2B3C4D5E6F7A8B9C0D1E2F3A4B5C6D7E8F9A0B1C:
        uid:-::::1677815220::89AB::Zoë Example\x3a `release` <zoe@example.com>::::::::::0:
        uid:-::::1677815220::CDEF::Zoë Example (C\x3a\\keys) <zoe@example.org>::::::::::0:
        pub:r:4096:1:2F2E1C1D3A4B5C6D:1500000000:1900000000::-:::scSC:::::::0:
        fpr:::::::::0123456789ABCDEF0123456789ABCDEF01234567:
        uid:r::::1500000000::CDEF::Retired Example <retired@example.com>::::::::::0:
      COLONS

      LISTING_WITHOUT_USER = <<~COLONS.freeze
        pub:-:255:22:9C0D1E2F3A4B5C6D7E8F9A0B:1751136988:::-:::scESC:::::ed25519:::0:
        fpr:::::::::#{ADA}:
      COLONS

      module Sanitization
        module Tests
          extend ActiveSupport::Concern

          included do
            test "shows control characters in user ids as escapes, so they can't break out of their code span" do
              assert_equal "`Ada\\n[link](https://example.com)`",
                           GpgKeys::Sanitization.code("Ada\n[link](https://example.com)")
            end

            test "shows invisible format characters in user ids as escapes" do
              assert_equal "`Ada \\u202E<moc.elpmaxe@ada> \\u200B\\u2028`",
                           GpgKeys::Sanitization.code("Ada \u202E<moc.elpmaxe@ada> \u200B\u2028")
            end

            test "unescapes bytes that aren't utf-8 without breaking the user id" do
              assert_equal "`Ada \u{FFFD}`", GpgKeys::Sanitization.code(GpgKeys::Sanitization.unescape('Ada \x80'))
            end

            test "shows blank-rendering characters in user ids as escapes" do
              assert_equal "`Ada\\u3164 Example`", GpgKeys::Sanitization.code("Ada\u3164 Example")
            end

            test "keeps the spaces around user ids and shows empty ones" do
              assert_equal "`  Ada  `", GpgKeys::Sanitization.code(" Ada ")
              assert_equal "(empty)", GpgKeys::Sanitization.code("")
            end

            test "shows spaces that look ordinary but aren't as escapes" do
              assert_equal "`Ada\\u00A0Example\\u3000\\u2800`", GpgKeys::Sanitization.code("Ada\u00A0Example\u3000\u2800")
            end

            test "doesn't pad a user id of only spaces" do
              assert_equal "` `", GpgKeys::Sanitization.code(" ")
            end

            test "leaves a malformed byte escape as it is" do
              assert_equal "xZZ :", GpgKeys::Sanitization.unescape('\xZZ \x3a')
            end

            test "shows a typed backslash differently from an escaped hidden character" do
              assert_equal "`Ada \\\\u202E \\u202E`", GpgKeys::Sanitization.code("Ada \\u202E \u202E")
            end
          end
        end
      end

      include Sanitization::Tests

      setup do
        @keys = GpgKeys.parse(LISTING).keys.to_h { |key| [key.fingerprint, key] }
        @revoked = GpgKeys.parse(LISTING.sub("uid:-::::1773151025", "uid:r::::1773151025")).keys.first
        @no_user = GpgKeys.parse(LISTING_WITHOUT_USER).keys.first
      end

      test "parses each primary key by its fingerprint, with its first user id" do
        assert_equal Hash(ADA => "Ada Example <ada@example.com>", ZOE => "Zoë Example: `release` <zoe@example.com>",
                          RETIRED => "Retired Example <retired@example.com>"),
                     @keys.transform_values(&:uid)
      end

      test "parses each key's subkeys" do
        assert_equal [ADA_SUBKEY], @keys[ADA].subkeys.map(&:fingerprint)
      end

      test "lists a key's other user ids, its details and each subkey's" do
        assert_equal ["Also `Ada Example <ada@example.org>`",
                      "ed25519, sign and certify, created 2025-06-28, doesn't expire",
                      "Subkey `#{ADA_SUBKEY}`: cv25519, encrypt, created 2025-06-28, doesn't expire"],
                     @keys[ADA].lines
      end

      test "lists each key by its fingerprint and first user id, followed by its other lines" do
        assert_equal <<~KEYS.chomp, GpgKeys.parse(LISTING).to_s
          - `#{ADA}`: `Ada Example <ada@example.com>`
            - Also `Ada Example <ada@example.org>`
            - ed25519, sign and certify, created 2025-06-28, doesn't expire
            - Subkey `#{ADA_SUBKEY}`: cv25519, encrypt, created 2025-06-28, doesn't expire
          - `#{ZOE}`: `` Zoë Example: `release` <zoe@example.com> ``
            - Also `Zoë Example (C:\\\\keys) <zoe@example.org>`
            - ed25519, sign and certify, created 2023-03-03, doesn't expire
          - `#{RETIRED}`: `Retired Example <retired@example.com>` (revoked)
            - rsa4096, sign and certify, created 2017-07-14, expires 2030-03-17, revoked
        KEYS
      end

      test "a key differs once one of its user ids is revoked" do
        refute_equal @keys[ADA], @revoked
        assert_equal "`Ada Example <ada@example.com>` (revoked)", @revoked.to_s
      end

      test "raises when gpg lists a key without a fingerprint, even if its subkey has one" do
        assert_raises RuntimeError, match: /gpg listed a key without a fingerprint/ do
          GpgKeys.parse(<<~COLONS)
            pub:-:255:22:9C0D1E2F3A4B5C6D7E8F9A0B:1751136988:::-:::scESC:::::ed25519:::0:
            sub:-:255:18:96A5B4C3D2E1F00F1E2D3C:1751136988::::::e:::::cv25519::
            fpr:::::::::#{ADA_SUBKEY}:
          COLONS
        end
      end

      test "rejects a fingerprint listed more than once" do
        assert_raises RuntimeError, match: /Duplicate Node.js release key IDs #{ADA}/ do
          GpgKeys.parse(LISTING + LISTING)
        end
      end

      test "describes an invalid elgamal subkey" do
        key = GpgKeys.parse(<<~COLONS).keys.first
          pub:-:4096:1:2F2E1C1D3A4B5C6D:1500000000:::-:::scSC:::::::0:
          fpr:::::::::#{ADA}:
          sub:i:2048:16:3A4B5C6D7E8F9A0B:1500000000::::::e:::::::
          fpr:::::::::#{ADA_SUBKEY}:
        COLONS

        assert_equal "Subkey `#{ADA_SUBKEY}`: elg2048, encrypt, created 2017-07-14, doesn't expire, invalid",
                     key.lines.last
      end

      test "describes a key without a user id" do
        assert_equal "(no user ID)", @no_user.to_s
      end

      test "describes an rsa key by its size, with its expiry and revocation" do
        assert_equal ["rsa4096, sign and certify, created 2017-07-14, expires 2030-03-17, revoked"],
                     @keys[RETIRED].lines
      end
    end
  end
end
