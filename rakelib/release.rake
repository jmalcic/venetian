# frozen_string_literal: true

require "open-uri"
require "tmpdir"
require_relative "../lib/venetian/gemspec"
require_relative "../lib/venetian/upstream"

module ReleaseTaskHelpers # :nodoc: all
  class VenetianGemHelper < Bundler::GemHelper
    def initialize(*, namespace: nil, **)
      super(*, **)
      @namespace = namespace
    end

    def install
      namespace @namespace do
        super
      end
    end
  end

  PLAYWRIGHT_ZIP = "playwright.zip"

  def download_and_unzip(url, destination_dir)
    with_tmp_zip_pathname do |pathname|
      pathname.binwrite URI.open(url).read # rubocop:disable Security/Open
      system "unzip", "-q", "-o", pathname.to_path, "-d", destination_dir, exception: true
    end
  end

  def copy_files(files, to)
    files.each do |file|
      mkdir_p File.join(to, File.dirname(file))
      cp file, File.join(to, File.dirname(file))
    end
  end

  def write_script(path, script, chmod: true)
    File.write path, script
    chmod 0o755, path if chmod
  end

  def write_gemspec(path, gemspec)
    File.write path, gemspec.to_ruby
  end

  def install_release_tasks_for(platform)
    VenetianGemHelper.new(Pathname.new(__dir__).join("..", "tmp", platform).expand_path, "venetian-#{platform}",
                          namespace: platform)
                     .install
  end

  private

  def with_tmp_zip_pathname(&block)
    Dir.mktmpdir do |tmpdir|
      Pathname.new(tmpdir).join(PLAYWRIGHT_ZIP).then(&block)
    end
  end
end

Venetian::Upstream.download_urls.each do |platform, url|
  namespace platform do
    include ReleaseTaskHelpers

    directory "exe/#{platform}"
    CLEAN.include File.join("exe", platform)

    file "exe/#{platform}/node" => "exe/#{platform}" do
      download_and_unzip url, File.join("exe", platform)
    end

    directory "tmp/#{platform}"
    CLEAN.include "tmp/#{platform}"

    file "tmp/#{platform}/venetian-#{platform}.gemspec" => %W[tmp/#{platform} exe/#{platform}/node] do
      write_gemspec File.join("tmp", platform, "venetian-#{platform}.gemspec"), Venetian::Upstream.build_gemspec_for(platform)
    end

    task install_tasks: "tmp/#{platform}/venetian-#{platform}.gemspec" do # rubocop:disable Rake/Desc
      copy_files Venetian::Upstream.base_files, File.join("tmp", platform)
      cp_r File.join("exe", platform), File.join("tmp", platform, "exe", platform), remove_destination: true
      install_release_tasks_for platform
    end

    %w[build install release].each do |name|
      task "#{name}_platform": :install_tasks do # rubocop:disable Rake/Desc
        Rake::Task["#{platform}:#{name}"].invoke
      end

      Rake::Task[name].enhance %W[#{platform}:#{name}_platform] unless name == "build"
    end
  end
end
