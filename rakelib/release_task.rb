# frozen_string_literal: true

require "json"
require "open-uri"
require "tmpdir"
require "playwright/version"
require_relative "../lib/venetian/gemspec"
require_relative "../lib/venetian/upstream"
require_relative "release_task/helpers"
require_relative "release_task/platform_tasks"
require_relative "release_task/versioning"

class ReleaseTask # :nodoc:
  include Rake::DSL
  include Helpers
  include Versioning

  def self.create
    new.define
  end

  def define
    core_package_tasks
    PlatformTasks.create_for(*Venetian::Upstream::NATIVE_PLATFORMS.keys)
    sync_version_task
  end

  private

  def core_package_tasks
    directory "tmp/playwright-core"
    CLEAN.include "tmp/playwright-core"

    file "tmp/playwright-core/package" => "tmp/playwright-core" do
      with_tmp_download_pathname "tgz" do |pathname|
        pathname.binwrite URI.open(Venetian::Upstream.playwright_core_url).read # rubocop:disable Security/Open
        system "tar", "-xzf", pathname.to_path, "-C", "tmp/playwright-core", exception: true
      end
    end
  end
end
