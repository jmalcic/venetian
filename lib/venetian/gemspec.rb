# frozen_string_literal: true

module Venetian
  GEMSPEC = Gem.loaded_specs.values.reverse.find do |spec|
    spec.gem_dir == Pathname.new(__dir__).join("..", "..").expand_path.to_path
  end
end
