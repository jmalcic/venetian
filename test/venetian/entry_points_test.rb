# frozen_string_literal: true

require "test_helper"

module Venetian
  class EntryPointsTest < Minitest::Test
    test "Capybara-free entry point loads on its own" do
      Dir.mktmpdir do |dir|
        FileUtils.touch(File.join(dir, "node"))

        assert_loads format(<<~RUBY, dir), Executable::INSTALL_DIR_ENV_VAR => dir
          module Rails
            class Railtie
              def self.rake_tasks(*) = nil
              def self.initializer(*) = nil
            end
          end
          require "venetian/playwright"
          abort "Capybara loaded" if defined?(Capybara)
          abort "Railtie loaded" if defined?(Venetian::Railtie)
          abort "unexpected command" unless Venetian::Executable.cli_command == "%1$s/node %1$s/package/cli.js"
        RUBY
      end
    end

    test "full entry point loads when Rails namespace exists without railties" do
      assert_loads <<~RUBY
        module Rails; end
        require "venetian"
        abort "Railtie loaded" if defined?(Venetian::Railtie)
      RUBY
    end

    private

    def assert_loads(script, env = {})
      _, stderr, status = Bundler.with_unbundled_env do
        Open3.capture3(env, RbConfig.ruby, *load_path_args, "-e", script)
      end

      assert_predicate status, :success?, stderr
    end

    def load_path_args
      [File.expand_path("../../lib", __dir__), *dependency_require_paths].collect_concat { |path| ["-I", path] }
    end

    def dependency_require_paths(spec = Gem.loaded_specs.fetch("venetian"), seen = Set.new)
      spec.runtime_dependencies.collect_concat do |dependency|
        next [] unless seen.add?(dependency.name)

        Gem.loaded_specs.fetch(dependency.name).then do |dependency_spec|
          dependency_spec.full_require_paths + dependency_require_paths(dependency_spec, seen)
        end
      end
    end
  end
end
