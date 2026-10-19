# frozen_string_literal: true

require "json"
require "rake/clean"
require_relative "../lib/venetian/upstream"
require_relative "tasks/helpers"
require_relative "release_task/platform_task"
require_relative "tasks/signatures"
require_relative "tasks/versioning"

class ReleaseTask # :nodoc:
  include Rake::DSL
  include Tasks::Helpers
  include Tasks::Signatures
  include Tasks::Versioning

  def self.create
    new.define
  end

  def define
    core_package_tasks
    PlatformTask.create_for(*Venetian::Upstream::NATIVE_PLATFORMS.keys)
    sync_version_task
    release_source_task
  end

  private

  def core_package_tasks
    directory "tmp/playwright-core"
    CLEAN.include "tmp/playwright-core"

    file "tmp/playwright-core/package" => "tmp/playwright-core" do
      download_and_verify_playwright
    end
  end

  def download_and_verify_playwright
    with_tmp_download_pathname "tgz" do |pathname|
      download Venetian::Upstream.playwright_core_url, pathname
      verify_checksum Venetian::Upstream.playwright_core_metadata_url, pathname,
                      method: :base64digest,
                      verifier: :npm,
                      extractor: ->(res) { res.dig("dist", "integrity")&.slice(/\Asha512-(.+)\z/m, 1) }
      system "tar", "-xzf", pathname.to_path, "-C", "tmp/playwright-core", exception: true
    end
  end
end
