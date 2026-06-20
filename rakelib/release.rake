# frozen_string_literal: true

require "open-uri"
require "tmpdir"
require "playwright/version"
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

  def released_playwright_version
    return unless released_spec

    released_spec.first.metadata["playwright_version"]
  end

  def patch
    gsub version_file, /(?<=\sVERSION = )".+"/, "\"#{patched_version_string}\""
    gsub version_file, /(?<=\sCOMPATIBLE_PLAYWRIGHT_VERSION = )".+"/, "\"#{Playwright::COMPATIBLE_PLAYWRIGHT_VERSION}\""
    gsub gemspec_file, /(?<="playwright-ruby-client", ">= )#{Gem::Version::VERSION_PATTERN}/, Playwright::VERSION
    system "bundle", "install", exception: true
    system "git", "commit", version_file, gemspec_file, "Gemfile.lock", "-m", "Bump version to #{patched_version_string}",
           exception: true
    system "git", "push", exception: true
  end

  private

  def with_tmp_zip_pathname(&block)
    Dir.mktmpdir do |tmpdir|
      Pathname.new(tmpdir).join(PLAYWRIGHT_ZIP).then(&block)
    end
  end

  def gsub(file, regexp, replacement)
    File.binwrite(file, File.binread(file).gsub(regexp, replacement))
  end

  def version_file
    Venetian.const_source_location(:VERSION).first
  end

  def gemspec_file
    File.join(__dir__, "..", "venetian.gemspec")
  end

  def patched_version_string
    [*current_version.segments[0..-2], current_version.segments.last.succ].join(".")
  end

  def current_version
    Gem::Version.new(Venetian::VERSION)
  end

  def released_spec
    released_specs.first.first
  end

  def released_specs
    @released_specs ||= Gem::SpecFetcher.fetcher
                                        .spec_for_dependency(Gem::Dependency.new(Venetian::GEMSPEC.name,
                                                                                 Venetian::GEMSPEC.version),
                                                             true)
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

desc "Checks if the current compatible Playwright version is greater than the released version"
task :sync_version do
  include ReleaseTaskHelpers

  patch unless released_playwright_version == Venetian::GEMSPEC.metadata["playwright_version"]
end
