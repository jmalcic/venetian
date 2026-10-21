# AGENTS.md

Guidance for coding agents working on Venetian. See `README.md` for what the gem does from a user's point of view.

## What this is

Venetian packages a Node.js binary and the `playwright-core` npm package in platform-specific gems, so
`playwright-ruby-client` and `capybara-playwright-driver` work without a separate Node.js setup. It's the same
packaging approach as Playwright for Python, Java and .NET, and as `tailwindcss-ruby`.

The source gem (`ruby` platform) has no driver. The release tasks assemble a driver for each platform in
`Venetian::Upstream::NATIVE_PLATFORMS` and build a `venetian-<platform>` gem from it.

## Setup

```bash
bin/setup                 # bundle install
bundle exec rake          # tests + RuboCop (the default task, what CI runs)
bundle exec rake test     # tests only
bundle exec rubocop       # lint only
N=/pattern/ bundle exec rake test   # run tests matching a name
```

Ruby >= 3.3. CI runs Ruby 3.3, 3.4 and 4.0 on Linux, 3.3 and 4.0 on Windows, and Rails 7.1, 7.2 and 8.0 on Linux.
To test against another Rails version, use a separate lockfile (gitignored):

```bash
BUNDLE_LOCKFILE=Gemfile.rails.lock RAILS_VERSION="~> 7.1.0" bundle exec rake test
```

The tests don't need a driver, browsers or network access. They stub the executable or use fixtures in `test/fixtures/`.
`print_args.exe` there is built from `print_args.c` on Windows (`gcc -O2 -s -municode`, from `ridk exec`).

When you run `bundle` locally, check that `Gemfile.lock` still has its `bundler (x.y.z) sha256=...` line under
`CHECKSUMS`. Restore it before committing if it's gone.

## Layout

```
lib/venetian.rb                          Full entry point: Capybara extensions + Railtie
lib/venetian/playwright.rb               Capybara-free entry point (require: "venetian/playwright"), Venetian.start
lib/venetian/core.rb                     Shared core: config accessors, Venetian.execute/system, Error
lib/venetian/version.rb                  VERSION, COMPATIBLE_PLAYWRIGHT_VERSION, NODE_VERSION
lib/venetian/upstream.rb                 NATIVE_PLATFORMS (gem platform => PlatformInfo), npm/nodejs.org URLs
lib/venetian/executable.rb               Finds and validates the bundled node + package/cli.js, runs commands
lib/venetian/browser_installer.rb        Browser and system-dependency installation, locking, writability checks
lib/venetian/trust_store.rb              Environment pointing the bundled Node at Ruby's certificate authorities
lib/venetian/playwright_create_extensions.rb   Prepended into Playwright's create: bundled CLI as default
lib/venetian/browser_runner_extensions.rb      Prepended into Capybara::Playwright::BrowserRunner: auto-install
lib/venetian/connection_extensions.rb       Prepended into Playwright::Connection: raises ForkedConnectionError after fork
lib/venetian/transport_extensions.rb        Prepended into Playwright::Transport: runs the bundled driver with TrustStore
lib/venetian/system_test_case_extension.rb     driven_by tracking, browser install before parallel forking
lib/venetian/railtie.rb                  Loads the Rake task, installs SystemTestCaseExtension
lib/venetian/gemspec.rb                  Venetian::GEMSPEC, the loaded spec for this gem
lib/tasks/venetian.rake                  User-facing venetian:install[browser] task
exe/playwright                           User-facing executable; exe/<platform>/ is generated and gitignored

rakelib/release_task.rb                  Release tasks: playwright-core download, per-platform tasks
rakelib/release_task/platform_task.rb    <platform>:build/install/release, Node.js download and assembly
rakelib/upstream_task.rb                 update_keys and update_node tasks (run by scheduled workflows)
rakelib/tasks/                           Shared task code: helpers, signatures, versioning, signed commits, PRs
rakelib/tasks/keys/                      Pinned Node.js release keys (node.kbx) and npm registry keys (npm.json)

test/test_helper.rb                      Requires everything and defines the test DSL
test/venetian/                           Tests for lib/venetian/
test/tasks/, test/upstream_task_test.rb  Tests for rakelib/
```

The assembled driver for each platform is `exe/<platform>/node` (`node.exe` on `x64-mingw-ucrt`) next to
`exe/<platform>/package/`, with `package/cli.js` as the entry point. `Executable.base_command` depends on this
layout, so keep it if you change the assembly. There's no wrapper script: `Executable.playwright_command`
(through `TrustStore::NodeCommand`) adds the Node options Venetian runs the driver with between the two.

## Releases and versions

- `Venetian::COMPATIBLE_PLAYWRIGHT_VERSION` must match `Playwright::COMPATIBLE_PLAYWRIGHT_VERSION` from
  `playwright-ruby-client`. When Dependabot bumps the client, `rake sync_version` (in the Pull Request workflow) bumps
  the gem version, the Playwright version and the gemspec requirement, and commits through the GitHub API.
- `Venetian::NODE_VERSION` is pinned. The Update Node workflow opens a PR for each new Node.js LTS release.
- The Update Keys workflow opens a PR when the pinned signing keys in `rakelib/tasks/keys/` change. Downloads are
  checked against signed checksums (Node.js `SHASUMS256.txt.asc`, npm registry signatures), so don't bypass them.
- Releases happen on push to `main` when `rake release_source` says the current version isn't on RubyGems yet.
  This requires CI and the Verify Build workflow (`rake install`, which builds and installs every platform gem) to pass.
  To release, bump `VERSION` in `lib/venetian/version.rb`. Don't run `rake release` by hand.
- `rakelib/`, `Rakefile`, `.github/`, `upstream.rb` and `gemspec.rb` are owned by the maintainer (`CODEOWNERS`).
  Changes there need extra care: a broken release task means a broken release.

## Code style

- RuboCop with `rubocop-minitest` and `rubocop-rake`, new cops enabled, double-quoted strings. Fix offences instead of
  disabling cops or adding exclusions. If a class gets too long, split it up.
- `# frozen_string_literal: true` at the top of every Ruby file.
- Use anonymous argument forwarding (`*`, `**`, `&`, `...`) where it fits, like the rest of the code.
- Prefer `Pathname` (`join`, `dirname`, `mkpath`, `write`) to `File.join`/`File.expand_path` strings and `FileUtils`.
  Call `.to_path` only where a String is needed, e.g. for ENV values or APIs that return Strings. The older rake code
  still uses `File.join`; don't add more.
- Doc comments are RDoc. Modules and classes start with a `# # Title` heading and a one-line description; background
  on why they exist goes in the commit message. Public methods get a short comment saying what they return or do.
- Don't comment methods marked `# :nodoc:` or private methods. Put the reasoning in the commit message. A short
  inline comment on a genuinely non-obvious line is fine.
- Mark internal classes and modules `# :nodoc:` (`# :nodoc: all` for rake task classes). Public methods that only the
  gem itself calls are `# :nodoc:` too (e.g. `BrowserInstaller.browsers_path`), rather than documented API.
- Read `ENV` where it's used rather than taking it as an argument so tests can pass a Hash. Tests set ENV and restore
  it instead.
- Extensions to other gems are `*Extensions` modules prepended at the bottom of their own file, not monkey patches.
  The entry points (`lib/venetian.rb`, `lib/venetian/playwright.rb`) decide which ones load.
- Debug output only appears when `VENETIAN_DEBUG` is set. Keep the gem quiet by default.

## Tests

- Minitest only. Every test file `require "test_helper"` and nothing else. Add new requires to `test/test_helper.rb`.
- Classes subclass `Minitest::Test` and use the declarative DSL from `test_helper.rb`: `test "does something" do`,
  `setup do`, `teardown do`. No `def test_*`, no `Minitest::Spec`/`describe`/`it`, and no custom base test class.
- Split long test classes into nested concerns instead of disabling `Metrics` cops:

  ```ruby
  class ExecutableTest < Minitest::Test
    module Running
      module Tests
        extend ActiveSupport::Concern

        included do
          test "..." do
          end
        end

        private

        # helpers for this topic
      end
    end

    include Running::Tests
  end
  ```

  Name concerns after the topic (`Running`, `Discovery`), not the class under test. Helpers only one concern uses go
  in its `private` section; shared setup, teardown and stubbing helpers stay in the class.
- `assert_raises` takes `match:` to check the exception message.
- Restore any ENV you change in `teardown` or an `ensure`.
- Tests must pass on Windows too: watch out for path separators, `node.exe`, and commands run through `cmd.exe`.

## Commits and pull requests

- Commit messages are a single imperative sentence describing the behaviour change, with no type prefix, e.g.
  "Verify the Node.js and playwright-core downloads" or "Raise when gh can't say whether there's a pull request".
  Put the reasoning in the body if it isn't obvious.
- Commits are authored by the configured git user. Coding agents add only a `Co-Authored-By` trailer, with no other
  trailers such as session links.
- Work on a branch and open a PR against `main`. Don't push to `main` directly.
- Workflows use least-privilege `permissions` and `persist-credentials: false` on checkout. Keep that for new ones.
- Actions are locked in `.github/workflows/actions.lock`. After adding a workflow or changing its `uses:`, run
  `gh actions-lock` (from `gh extension install github/gh-actions-lock`) and commit the result. Don't edit the lockfile
  by hand.
