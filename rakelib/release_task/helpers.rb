# frozen_string_literal: true

class ReleaseTask
  module Helpers # :nodoc: all
    def with_tmp_download_pathname(extension, &block)
      Dir.mktmpdir do |tmpdir|
        Pathname.new(tmpdir).join("download.#{extension}").then(&block)
      end
    end

    def copy_files(files, to)
      files.each do |file|
        mkdir_p File.join(to, File.dirname(file))
        cp file, File.join(to, File.dirname(file))
      end
    end

    def gsub(file, regexp, replacement)
      File.binwrite(file, File.binread(file).gsub(regexp, replacement))
    end

    def write_gemspec(path, gemspec)
      File.write path, gemspec.to_ruby
    end
  end
end
