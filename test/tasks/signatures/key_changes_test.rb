# frozen_string_literal: true

require "test_helper"
require_relative "../../../rakelib/tasks/signatures"

module Tasks
  module Signatures
    class KeyChangesTest < Minitest::Test
      Version = Data.define(:id, :version) do
        def to_s
          "version #{version}"
        end
      end

      Keys = Data.define(:versions) do
        include KeyChanges

        def keys
          versions.map { |id, version| Version.new(id:, version:) }
        end

        def key_kind
          "test key"
        end
      end

      setup do
        @kept = { "kept" => 1 }
        @removals = Keys.new(versions: { **@kept, "removed" => 2, "changed" => 3 })
        @additions = Keys.new(versions: { **@kept, "changed" => 4, "added" => 5 })
      end

      test "lists each added, removed and changed key with its before and after" do
        assert_pattern do
          @removals.changes_to(@additions)
                   .collect { |change| [change.id, change.before&.version, change.after&.version] } =>
          [["removed", 2, nil], ["changed", 3, 4], ["added", nil, 5]]
        end
      end

      test "lists nothing when the keys are the same" do
        assert_empty Keys.new(versions: @kept).changes_to(Keys.new(versions: @kept))
      end

      test "describes each change with the collection's kind of key and its description of the key" do
        assert_equal ["- Removed test key `removed`: version 2", "- Changed test key `changed`: version 4",
                      "- Added test key `added`: version 5"],
                     Keys.new(versions: @removals.versions.except("kept"))
                         .changes_to(Keys.new(versions: @additions.versions.except("kept")))
                         .collect(&:to_s)
      end
    end
  end
end
