# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Test against another Rails version with a separate lockfile, e.g.
#   BUNDLE_LOCKFILE=Gemfile.rails.lock RAILS_VERSION="~> 7.1.0" bundle exec rake test
gem "actionpack", ENV.fetch("RAILS_VERSION", ">= 0")
gem "irb"
gem "minitest"
gem "minitest-mock"
gem "rake"
gem "rubocop"
gem "rubocop-minitest"
gem "rubocop-rake"
