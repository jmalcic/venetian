# frozen_string_literal: true

module Venetian
  class Railtie < Rails::Railtie # :nodoc:
    rake_tasks do
      load "tasks/venetian.rake"
    end

    initializer "venetian.system_test_setup" do
      ActiveSupport.on_load :action_dispatch_system_test_case do
        require "venetian/system_test_case_extension"
        prepend SystemTestCaseExtension
      end
    end
  end
end
