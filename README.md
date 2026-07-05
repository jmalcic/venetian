# Venetian

Want stable system tests with Playwright, but don't want a Heath Robinson/Rube Goldberg setup in CI to try to keep the Ruby gem and Node
package in sync? This gem packages a Node executable plus the common Playwright package, using builds produced by Playwright for other
languages.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add venetian --group test
```

## Usage

### Rails system tests

In your system test case, choose the Playwright driver. Venetian will provide the base command to run Playwright,
which you can still override by passing `:playwright_cli_executable_path`, and this plus any other options will be passed through 
to `capybara-playwright-driver`.

```ruby
require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :playwright
end
```

### Automatic browser and dependency installation

The gem will automatically install a browser and dependencies for you before attempting to use it.
Browsers are installed to `$XDG_CACHE_HOME/ms-playwright` on Linux, `~/Library/Caches/ms-playwright` on macOS, 
and `%LOCALAPPDATA%\ms-playwright` on Windows. In CI, you will want to 
[cache this directory](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching) 
to avoid downloads on every run.

On Linux,
[Playwright currently only officially supports Debian and Ubuntu](https://playwright.dev/docs/intro#system-requirements) 
due to e.g. differences between package managers and package names across distros, 
so dependency installation happens only if a compatible package manager is found.
Depending on what you're doing, you may not need to install dependencies, 
but if you do and your distro is unsupported, you will need to work out what you need and deal with that first.

When parallelizing tests, there's also the issue of multiple processes all trying to acquire the package manager lock:
if you use Rails system tests with `ActionDispatch::SystemTestCase`,
this is handled automatically by installing all required browsers before disabling auto-installation and then forking.

### Installing browsers manually

If you can't rely on automatic installation, you can use the included Rake task to install browsers.
With Rails this is included automatically when the gem is required.

```bash
$ RAILS_ENV=test rails venetian:install

# Or a specific browser
$ RAILS_ENV=test rails venetian:install[firefox]
```

Otherwise in your Rakefile add:

```ruby
load "tasks/venetian.rake"
```

And then run:

```bash
$ rake venetian:install
```

### Running Playwright yourself

The gem provides a `playwright` executable which you can use to run Playwright yourself.

```bash
$ playwright --version 
Version 1.61.1
```

### Getting more output

Noisy output during a test run is often frustrating, so the gem is quiet by default. 
You can get more output with `VENETIAN_DEBUG=1`.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. 
You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. 
To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, 
which will create a git tag for the version, push git commits and the created tag, 
and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jmalcic/venetian. 
This project is intended to be a safe, welcoming space for collaboration, and contributors are expected 
to adhere to the [code of conduct](https://www.ruby-lang.org/en/conduct/).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Venetian project's codebases, issue trackers, chat rooms and mailing lists is expected
to follow the [code of conduct](https://www.ruby-lang.org/en/conduct/).
