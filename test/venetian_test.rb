# frozen_string_literal: true

require "test_helper"

class VenetianTest < Minitest::Test
  test "gem has a version number" do
    refute_nil ::Venetian::VERSION
  end
end
