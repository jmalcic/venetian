# frozen_string_literal: true

module Venetian
  module SystemTestCaseExtension # :nodoc: all
    extend ActiveSupport::Concern

    module ParallelizationExtension
      def start
        ActionDispatch::SystemTestCase.venetian_before_fork
        super
      end
    end

    prepended do
      class_attribute :venetian_browser_type, default: :chromium, instance_writer: false

      if respond_to?(:parallelize_before_fork)
        parallelize_before_fork { venetian_before_fork }
      else
        ActiveSupport::Testing::Parallelization.prepend(ParallelizationExtension)
      end
    end

    class_methods do
      def driven_by(driver, options: {}, **)
        super

        self.venetian_browser_type = if driver == :playwright
                                       BrowserRunnerExtensions.browser_to_preinstall_from(options)
                                     end
      end

      def install_playwright_browsers
        venetian_browsers.presence.try do |browsers|
          browsers.each { |browser| BrowserInstaller.install(browser) }
          Venetian.auto_install_browsers = false
        end
      end

      def venetian_before_fork
        install_playwright_browsers if venetian_preinstall_browsers_before_fork?
      end

      private

      def venetian_preinstall_browsers_before_fork?
        Venetian.auto_install_browsers && defined? ActionDispatch::SystemTestCase
      end

      def venetian_browsers
        Minitest::Runnable.runnables
                          .select { |klass| klass < ActionDispatch::SystemTestCase && klass.driver&.name == :playwright }
                          .filter_map(&:venetian_browser_type)
                          .uniq
      end
    end
  end
end
