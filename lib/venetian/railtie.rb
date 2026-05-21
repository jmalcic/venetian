# frozen_string_literal: true

module Venetian
  class Railtie < Rails::Railtie # :nodoc:
    rake_tasks do
      load "tasks/venetian.rake"
    end
  end
end
