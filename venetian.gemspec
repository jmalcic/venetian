# frozen_string_literal: true

require_relative "lib/venetian/version"

Gem::Specification.new do |spec|
  spec.name = "venetian"
  spec.version = Venetian::VERSION
  spec.authors = ["Justin Malčić"]
  spec.email = ["j.malcic@me.com"]

  spec.summary = "Playwright executables for Ruby"
  spec.description = "Bundles the Playwright driver binary in platform-specific gem variants and " \
                     "integrates with `capybara-playwright-driver`."
  spec.homepage = "https://github.com/jmalcic/venetian"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = "https://malcic.codes/software/venetian"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["playwright_version"] = Venetian::COMPATIBLE_PLAYWRIGHT_VERSION

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/ .rubocop.yml rakelib/]) ||
        f.match?(%r{\Aexe/.+/}) # exclude platform binary subdirectories (exe/{platform}/...)
    end
  end

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "capybara-playwright-driver", ">= 0.5"
  spec.add_dependency "playwright-ruby-client", ">= 1.60.0"
end
