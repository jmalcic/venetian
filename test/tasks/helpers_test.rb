# frozen_string_literal: true

require "test_helper"
require_relative "../../rakelib/tasks/helpers"

module Tasks
  class HelpersTest < Minitest::Test
    CHECKSUMS_URL = "https://example.com/checksums"

    class Helped
      include Helpers
    end

    setup do
      @helped = Helped.new
      @tmpdir = Dir.mktmpdir
      @pathname = Pathname.new(@tmpdir).join("download")
      @pathname.binwrite "contents"
    end

    teardown do
      FileUtils.remove_entry @tmpdir
    end

    test "download streams the response to the pathname" do
      stub_uri_open "downloaded \r\n\x00 contents".b do
        @helped.download CHECKSUMS_URL, @pathname
      end

      assert_equal "downloaded \r\n\x00 contents".b, @pathname.binread
    end

    test "verify checksum passes when the published checksum matches" do
      Digest::SHA512.file(@pathname).hexdigest.then do |checksum|
        stub_uri_open checksum do
          assert_equal checksum, @helped.verify_checksum(CHECKSUMS_URL, @pathname)
        end
      end
    end

    test "verify checksum compares the digest in the given format" do
      Digest::SHA256.file(@pathname).base64digest.then do |checksum|
        stub_uri_open checksum do
          assert_equal checksum,
                       @helped.verify_checksum(CHECKSUMS_URL, @pathname, digest: Digest::SHA256, method: :base64digest)
        end
      end
    end

    test "verify checksum compares the checksum derived by the extractor" do
      Digest::SHA512.file(@pathname).hexdigest.then do |checksum|
        stub_uri_open "checksum: #{checksum}" do
          assert_equal checksum,
                       @helped.verify_checksum(CHECKSUMS_URL, @pathname,
                                               extractor: ->(res) { res.delete_prefix("checksum: ") })
        end
      end
    end

    test "verify checksum raises when the published checksum differs" do
      stub_uri_open Digest::SHA512.hexdigest("other contents") do
        assert_raises RuntimeError, match: /Checksum mismatch/ do
          @helped.verify_checksum CHECKSUMS_URL, @pathname
        end
      end
    end

    test "verify checksum raises when the extractor finds no checksum" do
      stub_uri_open Digest::SHA512.file(@pathname).hexdigest do
        assert_raises RuntimeError, match: /No checksum derived from #{CHECKSUMS_URL}/ do
          @helped.verify_checksum CHECKSUMS_URL, @pathname, extractor: ->(_) {}
        end
      end
    end

    test "verify checksum raises when the published checksum is empty" do
      stub_uri_open "" do
        assert_raises RuntimeError, match: /No checksum derived from #{CHECKSUMS_URL}/ do
          @helped.verify_checksum CHECKSUMS_URL, @pathname
        end
      end
    end

    %w[http://example.com/file file:///etc/passwd /etc/passwd ftp://example.com/file].each do |url|
      test "read https refuses #{url}" do
        stub_uri_open do
          assert_raises ArgumentError, match: /Refusing to open non-HTTPS URL/ do
            @helped.read_https url
          end
        end
      end
    end

    private

    def stub_uri_open(response = "", &)
      OpenURI.stub(:open_uri, ->(*, &block) { block.call(StringIO.new(response)) }, &)
    end
  end
end
