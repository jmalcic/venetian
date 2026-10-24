# frozen_string_literal: true

require "test_helper"

module Venetian
  class TrustStoreTest < Minitest::Test
    ENV_VARS = %w[SSL_CERT_FILE SSL_CERT_DIR].freeze

    setup do
      @original_env = ENV.to_h.slice(*ENV_VARS)
      ENV_VARS.each { |name| ENV.delete(name) }
    end

    teardown do
      ENV_VARS.each { |name| ENV[name] = @original_env[name] }
    end

    test "points Node at Ruby's default certificates" do
      assert_equal Hash("SSL_CERT_FILE" => OpenSSL::X509::DEFAULT_CERT_FILE, "SSL_CERT_DIR" => OpenSSL::X509::DEFAULT_CERT_DIR),
                   TrustStore.environment
    end

    test "points Node at certificates set in the environment" do
      ENV["SSL_CERT_FILE"] = "/certs/cert.pem"
      ENV["SSL_CERT_DIR"] = "/certs"

      assert_equal Hash("SSL_CERT_FILE" => "/certs/cert.pem", "SSL_CERT_DIR" => "/certs"), TrustStore.environment
    end

    test "has Node use Ruby's certificates instead of its bundled ones" do
      assert_equal %w[node --use-openssl-ca cli.js run-driver], TrustStore.node_command("node", "cli.js", "run-driver")
    end

    test "has Node use Ruby's certificates alongside other Node options" do
      ENV["NODE_OPTIONS"] = "--max-old-space-size=4096"

      assert_equal %w[node --use-openssl-ca cli.js], TrustStore.node_command("node", "cli.js")
    end

    test "leaves Node with its bundled certificates when Venetian is told to" do
      ENV["VENETIAN_BUNDLED_CA"] = "1"

      assert_node_left_alone
    end

    test "has Node use Ruby's certificates when Venetian isn't told to use the bundled ones" do
      ENV["VENETIAN_BUNDLED_CA"] = "0"

      assert_equal %w[node --use-openssl-ca cli.js], TrustStore.node_command("node", "cli.js")
    end

    test "leaves Node with its bundled certificates when Node options ask for them" do
      ENV["NODE_OPTIONS"] = "--max-old-space-size=4096 --use-bundled-ca"

      assert_node_left_alone
    end

    test "leaves Node with the system's certificates when Node options ask for them" do
      ENV["NODE_OPTIONS"] = "--max-old-space-size=4096 --use-system-ca"

      assert_node_left_alone
    end

    test "leaves Node with the system's certificates when the environment asks for them" do
      ENV["NODE_USE_SYSTEM_CA"] = "1"

      assert_node_left_alone
    end

    test "has Node use Ruby's certificates when the environment doesn't ask for the system's" do
      ENV["NODE_USE_SYSTEM_CA"] = "0"

      assert_equal %w[node --use-openssl-ca cli.js], TrustStore.node_command("node", "cli.js")
    end

    private

    def assert_node_left_alone
      assert_equal %w[node cli.js], TrustStore.node_command("node", "cli.js")
      assert_empty TrustStore.environment
    end
  end
end
