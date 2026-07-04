# frozen_string_literal: true

module Venetian
  module SystemTestCaseExtension # :nodoc:
    extend ActiveSupport::Concern

    prepended do
      class_attribute :venetian_browser_type, default: :chromium, instance_writer: false

      parallelize_before_fork do
        install_playwright_browsers if venetian_preinstall_browsers_before_fork?
      end
    end

    class_methods do # :nodoc:
      def driven_by(driver, options: {}, **)
        super

        self.venetian_browser_type = driver == :playwright ? options.fetch(:browser_type, :chromium).to_sym : nil
      end

      def install_playwright_browsers
        venetian_browsers.presence.try do |browsers|
          browsers.each { |browser| BrowserInstaller.install(browser) }
          Venetian.auto_install_browsers = false
        end
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
