# frozen_string_literal: true

require "test_helper"

module Venetian
  class EntryPointsTest < Minitest::Test
    EXECUTABLE = Gem.win_platform? ? "node.exe" : "node"

    test "Capybara-free entry point loads on its own" do
      Dir.mktmpdir do |dir|
        Pathname.new(dir).then do |root|
          root.join("package").tap(&:mkpath).join("cli.js").write("")
          root.join(EXECUTABLE).write("", perm: 0o755)
        end

        assert_loads format(<<~RUBY, dir, EXECUTABLE), Executable::INSTALL_DIR_ENV_VAR => dir
          module Rails
            class Railtie
              def self.rake_tasks(*) = nil
              def self.initializer(*) = nil
            end
          end
          require "venetian/playwright"
          abort "Capybara loaded" if defined?(Capybara)
          abort "Railtie loaded" if defined?(Venetian::Railtie)
          abort "unexpected command" unless Venetian::Executable.base_command == ["%1$s/%2$s", "%1$s/package/cli.js"]
        RUBY
      end
    end

    test "core loads without Playwright" do
      assert_loads <<~RUBY
        require "venetian/core"
        abort "Playwright loaded" if defined?(Playwright::Channel)
        abort "missing installer" unless defined?(Venetian::BrowserInstaller)
      RUBY
    end

    test "playwright executable passes through output and exit status" do
      Dir.mktmpdir do |dir|
        Pathname.new(dir).then do |root|
          create_fake_driver_in(root)

          output, status = run_executable("--version",
                                          Executable::INSTALL_DIR_ENV_VAR => dir, "PRINT_ARGS_STATUS" => "23")

          assert_equal "#{root.join("package", "cli.js")}\n--version\n", output.tr("\\", "/")
          assert_equal 23, status.exitstatus
        end
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
      [root_dir.join("lib").to_path, *dependency_require_paths].collect_concat { |path| ["-I", path] }
    end

    def dependency_require_paths(spec = Gem.loaded_specs.fetch("venetian"), seen = Set.new)
      spec.runtime_dependencies.collect_concat do |dependency|
        next [] unless seen.add?(dependency.name)

        Gem.loaded_specs.fetch(dependency.name).then do |dependency_spec|
          dependency_spec.full_require_paths + dependency_require_paths(dependency_spec, seen)
        end
      end
    end

    def create_fake_driver_in(dir)
      dir.join("package").tap(&:mkpath).join("cli.js").write("")
      if Gem.win_platform?
        FileUtils.cp(fixtures_dir.join("print_args.exe"), dir.join("node.exe"))
      else
        # Prints its arguments and exits with PRINT_ARGS_STATUS, like the fixture on Windows.
        dir.join("node").write(<<~SH, perm: 0o755)
          #!/bin/sh
          printf '%s\\n' "$@"
          exit "${PRINT_ARGS_STATUS:-0}"
        SH
      end
    end

    def run_executable(*args, env)
      Bundler.with_unbundled_env do
        Open3.capture2e(env, RbConfig.ruby, *load_path_args, root_dir.join("exe", "playwright").to_path, *args)
      end
    end

    def root_dir
      Pathname.new(__dir__).join("..", "..").expand_path
    end
  end
end
