# frozen_string_literal: true

module Venetian
  module TransportExtensions # :nodoc:
    private

    def run_driver_with_open3
      return super unless Executable.cli_command?(@driver_executable_path)

      # Windows doesn't accept the pgroup option
      Open3.popen3(TrustStore.environment, *Executable.playwright_command("run-driver"),
                   **({ pgroup: true } unless Gem.win_platform?).to_h)
    end
  end
end

Playwright::Transport.prepend(Venetian::TransportExtensions)
