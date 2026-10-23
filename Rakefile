# frozen_string_literal: true

require "bundler/setup"
require "bundler/gem_tasks"

# With BUNDLE_ONLY=sync, neither the test and lint gems nor this gem are installed and set up
if Bundler.settings[:only].then { |groups| groups.empty? || groups.include?(:default) }
  require "minitest/test_task"

  Minitest::TestTask.create

  require "rubocop/rake_task"

  RuboCop::RakeTask.new

  task default: %i[test rubocop]
else
  require "pathname"

  $LOAD_PATH.unshift Pathname(__dir__).join("lib").to_path
end

import "rakelib/release.rake"
import "rakelib/upstream.rake"
