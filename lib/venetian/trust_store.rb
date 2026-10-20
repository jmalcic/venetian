# frozen_string_literal: true

require "openssl"

module Venetian
  # # Trust Store
  #
  # Points the bundled Node at the certificate authorities Ruby's OpenSSL trusts.
  module TrustStore
    CERT_FILE_ENV_VAR = OpenSSL::X509::DEFAULT_CERT_FILE_ENV # :nodoc:
    CERT_DIR_ENV_VAR = OpenSSL::X509::DEFAULT_CERT_DIR_ENV # :nodoc:
    USE_OPENSSL_CA = "--use-openssl-ca" # :nodoc:
    USE_BUNDLED_CA = "--use-bundled-ca" # :nodoc:
    BUNDLED_CA_ENV_VAR = "VENETIAN_BUNDLED_CA" # :nodoc:

    class << self
      # Returns whether to run Node with the certificate authorities Ruby's OpenSSL trusts, which it does unless
      # +VENETIAN_BUNDLED_CA+ is set or +NODE_OPTIONS+ includes +--use-bundled-ca+.
      def enabled?
        !ENV.key?(BUNDLED_CA_ENV_VAR) && !ENV.fetch("NODE_OPTIONS", "").split.include?(USE_BUNDLED_CA)
      end

      # Returns the environment variables pointing Node at the certificates Ruby's OpenSSL trusts, if #enabled?.
      def environment
        return {} unless enabled?

        { CERT_FILE_ENV_VAR => ENV.fetch(CERT_FILE_ENV_VAR, OpenSSL::X509::DEFAULT_CERT_FILE),
          CERT_DIR_ENV_VAR => ENV.fetch(CERT_DIR_ENV_VAR, OpenSSL::X509::DEFAULT_CERT_DIR) }
      end

      # Returns the Node command with the given arguments, having Node use those certificates instead of its bundled
      # ones if #enabled?.
      def node_command(node, *)
        [node, *(USE_OPENSSL_CA if enabled?), *]
      end
    end

    module NodeCommand # :nodoc:
      def playwright_command(...)
        TrustStore.node_command(*super)
      end
    end

    private

    def system(*, **)
      super(TrustStore.environment, *, **)
    end

    def exec(*, **)
      super(TrustStore.environment, *, **)
    end

    def spawn(*, **)
      super(TrustStore.environment, *, **)
    end
  end
end
