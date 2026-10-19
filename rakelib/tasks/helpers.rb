# frozen_string_literal: true

require "digest"
require "open-uri"
require "pathname"
require "tmpdir"

module Tasks
  module Helpers # :nodoc: all
    def with_tmp_download_pathname(extension, &block)
      Dir.mktmpdir do |tmpdir|
        Pathname.new(tmpdir).join("download.#{extension}").then(&block)
      end
    end

    def open_https(url, &)
      URI(url).tap { |uri| raise ArgumentError, "Refusing to open non-HTTPS URL #{url}" unless uri.is_a?(URI::HTTPS) }
              .open(&)
    end

    def read_https(url)
      open_https(url, &:read)
    end

    def download(url, pathname)
      open_https(url) do |io|
        pathname.open("wb") { |file| IO.copy_stream(io, file) }
      end
    end

    def verify_checksum(source_url, pathname, digest: Digest::SHA512, method: :hexdigest, extractor: :itself)
      unless (expected = extractor.to_proc.call(read_https(source_url))) && !expected.empty?
        raise "No checksum derived from #{source_url}"
      end

      digest.file(pathname).public_send(method).tap do |actual|
        raise "Checksum mismatch for #{pathname}: expected #{expected}, got #{actual}" unless expected == actual
      end
    end

    def copy_files(files, to)
      files.each do |file|
        mkdir_p File.join(to, File.dirname(file))
        cp file, File.join(to, File.dirname(file))
      end
    end

    def gsub(file, regexp, replacement)
      File.binread(file).then do |content|
        raise ArgumentError, "#{regexp.inspect} matches nothing in #{file}" unless content.match?(regexp)

        File.binwrite(file, content.gsub(regexp) { replacement })
      end
    end

    def write_gemspec(path, gemspec)
      File.write path, gemspec.to_ruby
    end
  end
end
