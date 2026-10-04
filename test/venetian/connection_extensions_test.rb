# frozen_string_literal: true

require "test_helper"

module Venetian
  class ConnectionExtensionsTest < Minitest::Test
    class FakeTransport
      attr_reader :messages

      def initialize
        @messages = []
      end

      def on_message_received(&) = nil
      def on_driver_crashed(&) = nil
      def on_driver_closed(&) = nil

      def send_message(message)
        @messages << message
      end
    end

    setup do
      @transport = FakeTransport.new
      @connection = Playwright::Connection.new(@transport)
    end

    test "sends messages from the process that started the connection" do
      @connection.async_send_message_to_server("", "initialize", {})

      assert_equal(["initialize"], @transport.messages.collect { |message| message[:method] })
    end

    test "raises instead of sending messages after forking" do
      pid = Process.pid

      Process.stub(:pid, pid + 1) do
        assert_raises ForkedConnectionError, match: /belongs to process #{pid}/ do
          @connection.async_send_message_to_server("", "initialize", {})
        end
      end

      assert_empty @transport.messages
    end
  end
end
