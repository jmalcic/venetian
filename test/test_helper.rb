# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "venetian"

require "minitest/autorun"
require "minitest/mock"
require "fileutils"
require "tmpdir"
require "open3"
require "rbconfig"
require "active_support/core_ext/object/with"
require "active_support/concern"
require "active_support/testing/constant_stubbing"

module Minitest
  class Test
    include ActiveSupport::Testing::ConstantStubbing

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
      test_classes.reverse_each { |klass| klass.__send__(:_setup_blocks).each { |b| instance_exec(&b) } }
    end

    def teardown
      test_classes.each { |klass| klass.__send__(:_teardown_blocks).each { |b| instance_exec(&b) } }
    end

    TRUST_STORE_OPT_OUTS = %w[VENETIAN_BUNDLED_CA NODE_OPTIONS NODE_USE_SYSTEM_CA].freeze

    setup do
      @original_trust_store_opt_outs = ENV.to_h.slice(*TRUST_STORE_OPT_OUTS)
      TRUST_STORE_OPT_OUTS.each { |name| ENV.delete(name) }
    end

    teardown do
      TRUST_STORE_OPT_OUTS.each { |name| ENV[name] = @original_trust_store_opt_outs[name] }
    end

    private

    def test_classes
      self.class.ancestors.select { |ancestor| ancestor.is_a?(Class) && ancestor <= Test }
    end

    def fixtures_dir
      Pathname.new(__dir__).join("fixtures")
    end

    def assert_raises(exception_class, message = nil, match: nil, &block)
      super(exception_class, *message, &block).tap do |exception|
        assert_match match, exception.message if match
      end
    end
  end
end
