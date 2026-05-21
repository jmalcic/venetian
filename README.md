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

In your system test case, choose the Playwright driver. Venetian will provide the base command to run Playwright,
which you can still override by passing `:playwright_cli_executable_path`, and this plus any other options will be passed through 
to `capybara-playwright-driver`. If you specify a browser, this will be automatically downloaded if necessary.

```ruby
require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :playwright
end
```

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
