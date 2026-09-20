# frozen_string_literal: true

class ReleaseTask
  module Versioning # :nodoc: all
    def sync_version_task
      desc "Patches the version if the current compatible Playwright version is greater than the released version"
      task :sync_version do
        patch unless released_playwright_version_current?
      end
    end

    private

    def released_playwright_version_current?
      released_playwright_version == Playwright::COMPATIBLE_PLAYWRIGHT_VERSION
    end

    def patch
      gsub version_file, /(?<=\sVERSION = )".+"/, "\"#{patched_version_string}\""
      gsub version_file, /(?<=\sCOMPATIBLE_PLAYWRIGHT_VERSION = )".+"/, "\"#{Playwright::COMPATIBLE_PLAYWRIGHT_VERSION}\""
      gsub gemspec_file, /(?<="playwright-ruby-client", ">= )#{Gem::Version::VERSION_PATTERN}/, Playwright::VERSION
      system Hash("BUNDLE_FROZEN" => "false"), "bundle", "install", exception: true
      system "git", "commit", version_file, gemspec_file, "Gemfile.lock", "-m",
             "Bump version to #{patched_version_string}", exception: true
      system "git", "push", exception: true
    end

    def released_playwright_version
      return unless released_spec

      released_spec.first.metadata["playwright_version"]
    end

    def version_file
      Venetian.const_source_location(:VERSION).first
    end

    def gemspec_file
      File.join(__dir__, "..", "..", "venetian.gemspec")
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
      @released_specs ||= Gem::SpecFetcher.fetcher.spec_for_dependency(gem_dependency, true)
    end

    def gem_dependency
      Gem::Dependency.new(Venetian::GEMSPEC.name, Venetian::GEMSPEC.version)
    end
  end
end
