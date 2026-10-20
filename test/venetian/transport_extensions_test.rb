# frozen_string_literal: true

require "test_helper"

module Venetian
  class TransportExtensionsTest < Minitest::Test
    BASE_COMMAND = %w[/bundled/node /bundled/package/cli.js].freeze
    DRIVER_COMMAND = %w[/bundled/node --use-openssl-ca /bundled/package/cli.js run-driver].freeze
    ENVIRONMENT = { "SSL_CERT_FILE" => "/certs/cert.pem" }.freeze

    setup do
      @popen_mock = Minitest::Mock.new
    end

    test "runs the bundled driver with Ruby's trust store" do
      @popen_mock.expect(:call, nil, [ENVIRONMENT, *DRIVER_COMMAND], pgroup: true)

      with_stubs do
        run_driver(Executable.cli_command)
      end

      assert_mock @popen_mock
    end

    test "runs the bundled driver without a process group on Windows" do
      @popen_mock.expect(:call, nil, [ENVIRONMENT, *DRIVER_COMMAND])

      with_stubs windows: true do
        run_driver(Executable.cli_command)
      end

      assert_mock @popen_mock
    end

    test "runs other drivers as Playwright would" do
      @popen_mock.expect(:call, nil, ["/custom run-driver", { pgroup: true }])

      with_stubs do
        run_driver("/custom")
      end

      assert_mock @popen_mock
    end

    private

    def run_driver(command)
      Playwright::Transport.new(playwright_cli_executable_path: command).send(:run_driver_with_open3)
    end

    def with_stubs(windows: false, &)
      Executable.stub(:base_command, BASE_COMMAND) do
        TrustStore.stub(:environment, ENVIRONMENT) do
          Gem.stub(:win_platform?, windows) do
            Open3.stub(:popen3, @popen_mock, &)
          end
        end
      end
    end
  end
end
