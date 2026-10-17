# frozen_string_literal: true

require "playwright/version"
require_relative "../../lib/venetian/gemspec"
require_relative "../../lib/venetian/version"
require_relative "helpers"

module Tasks
  module Versioning # :nodoc: all
    include Helpers

    CLIENT_REQUIREMENT = %("~> #{Gem::Version.new(Playwright::VERSION).segments.first(2).join(".")}.0").freeze
    VERSION_FILE = Venetian.const_source_location(:VERSION).first
    GEMSPEC_FILE = File.join(__dir__, "..", "..", "venetian.gemspec")
    CURRENT_VERSION = Gem::Version.new(Venetian::VERSION)

    def sync_version_task
      desc "Patches the version if the current compatible Playwright version is greater than the released version"
      task :sync_version do
        patch unless released_playwright_version_current?
      end
    end

    def release_source_task
      desc "Prints the source the current version was released to, if it has been released"
      task :release_source do
        puts released_spec&.last&.uri
      end
    end

    private

    def released_playwright_version_current?
      released_playwright_version == Playwright::COMPATIBLE_PLAYWRIGHT_VERSION
    end

    def patch
      patch_version_file
      patch_gemspec
      update_lockfile
      system "git", "commit", version_file, gemspec_file, "Gemfile.lock", "-m",
             "Bump version to #{patched_version_string}", exception: true
      system "git", "push", exception: true
    end

    def patch_version_file
      patch_version_constants VERSION: patched_version_string,
                              COMPATIBLE_PLAYWRIGHT_VERSION: Playwright::COMPATIBLE_PLAYWRIGHT_VERSION
    end

    def patch_version_constants(**values)
      values.each do |name, value|
        gsub version_file, /(?<=\s#{name} = )".+"/, value.dump
      end
    end

    def patch_gemspec
      gsub gemspec_file, /(?<="playwright-ruby-client", ).+$/, CLIENT_REQUIREMENT
    end

    def update_lockfile
      system Hash("BUNDLE_FROZEN" => "false"), "bundle", "install", exception: true
    end

    def released_playwright_version
      return unless released_spec

      released_spec.first.metadata["playwright_version"]
    end

    def gemspec_file
      GEMSPEC_FILE
    end

    def version_file
      VERSION_FILE
    end

    def patched_version_string
      next_patch_version CURRENT_VERSION
    end

    def next_patch_version(version)
      [*version.segments[0..-2], version.segments.last.succ].join(".")
    end

    def released_spec
      released_specs.first.first
    end

    def released_specs
      @released_specs ||= Gem::SpecFetcher.fetcher.spec_for_dependency(gem_dependency, false).tap do |_, errors|
        raise errors.first.error unless errors.empty?
      end
    end

    def gem_dependency
      Gem::Dependency.new(Venetian::GEMSPEC.name, Venetian::GEMSPEC.version)
    end
  end
end
