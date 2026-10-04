# frozen_string_literal: true

module Venetian
  # # Forked Connection Error
  #
  # Raised when a Playwright connection is used by a process forked from the one that started it.
  class ForkedConnectionError < Error
    def initialize(pid) # :nodoc:
      super("This Playwright connection belongs to process #{pid}, so can't be used after forking. " \
            "Start Playwright again in this process instead.")
    end
  end

  module ConnectionExtensions # :nodoc:
    def initialize(...)
      @venetian_pid = Process.pid
      super
    end

    def async_send_message_to_server(...)
      raise ForkedConnectionError, @venetian_pid unless Process.pid == @venetian_pid

      super
    end
  end
end

Playwright::Connection.prepend(Venetian::ConnectionExtensions)
