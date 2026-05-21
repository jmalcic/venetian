# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "venetian"

require "minitest/autorun"
require "minitest/mock"
require "fileutils"
require "tmpdir"

module Minitest
  class Test
    class << self
      def setup(&block)
        _setup_blocks << block
      end

      def teardown(&block)
        _teardown_blocks << block
      end

      # Declarative test definition, analogous to ActiveSupport::Testing::Declarative.
      def test(name, &)
        define_method("test_#{name.gsub(/\s+/, "_")}", &)
      end

      private

      def _setup_blocks
        @_setup_blocks ||= []
      end

      def _teardown_blocks
        @_teardown_blocks ||= []
      end
    end

    def setup
      self.class.__send__(:_setup_blocks).each { |b| instance_exec(&b) }
    end

    def teardown
      self.class.__send__(:_teardown_blocks).each { |b| instance_exec(&b) }
    end

    private

    def assert_raises(exception_class, message = nil, match: nil, &block)
      super(exception_class, *message, &block).tap do |exception|
        assert_match match, exception.message if match
      end
    end
  end
end
