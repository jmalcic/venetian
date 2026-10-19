# frozen_string_literal: true

module Tasks
  module Signatures # :nodoc: all
    module KeyChanges
      Change = Data.define(:keys, :id, :before, :after) do
        def self.from_differences(start, removed, added)
          (removed + added).uniq(&:id).collect do |changed_key|
            Change.new(keys: start, id: changed_key.id,
                       before: removed.find { |key| key.id == changed_key.id },
                       after: added.find { |key| key.id == changed_key.id })
          end
        end

        def to_s
          "- #{change} #{keys.key_kind} `#{id}`: #{after || before}"
        end

        def change
          return "Added" unless before
          return "Removed" unless after

          "Changed"
        end
      end

      def initialize(...)
        super
        ensure_no_duplicates!
      end

      def changes_to(other)
        Change.from_differences(self, keys - other.keys, other.keys - keys)
      end

      private

      def ensure_no_duplicates!
        raise "Duplicate #{key_kind} IDs #{duplicates.join(", ")}" unless duplicates.empty?
      end

      def duplicates
        keys.collect(&:id)
            .tally
            .select { |_id, count| count > 1 }
            .keys
      end
    end
  end
end
