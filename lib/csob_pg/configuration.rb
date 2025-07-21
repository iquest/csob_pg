# frozen_string_literal: true

require 'yaml'
require 'erb'
require_relative 'client'

# Module for CsobPaymentGateway
# This module is used to configure the CsobPaymentGateway
# It provides methods to set the configuration and create a client
# The client is used to interact with the CsobPaymentGateway API
# The configuration is loaded from environment variables or set to default values
# The configuration can be overridden by calling the configure method
module CsobPaymentGateway
  class << self
    def configure
      yield(configuration)
    end

    def configuration
      @configuration ||= Configuration.new(
        gateway_url: gateway_url,
        return_url: ENV.fetch('CSOB_RETURN_URL', ''),
        merchant_id: ENV.fetch('CSOB_MERCHANT_ID', ''),
        client_private_key: ENV.fetch('CSOB_CLIENT_PRIVATE_KEY', ''),
        service_public_key: ENV.fetch('CSOB_SERVICE_PUBLIC_KEY', ''),
        client_public_key: ENV.fetch('CSOB_CLIENT_PUBLIC_KEY', nil),
        logger: nil
      )
    end

    def client(**args)
      @client ||= create_client(**args)
    end

    # rubocop:disable Metrics/MethodLength
    def gateway_url
      environment = (ENV['CSOB_ENVIRONMENT'] || :production).to_sym
      version = (ENV['CSOB_VERSION'] || '1.9').to_s

      base_url = environment == :production ? 'https://api.platebnibrana.csob.cz' : 'https://iapi.iplatebnibrana.csob.cz'
      base_url += case version.to_s
                  when '1.8'
                    '/api/v1.8'
                  when '1.9'
                    '/api/v1.9'
                  else
                    raise 'Unsupported API version'
                  end
      base_url
    end
    # rubocop:enable Metrics/MethodLength

    def create_client(return_url: nil, merchant_id: nil, client_key: nil, client_pub_key: nil)
      Client.new(
        url: configuration.gateway_url,
        return_url: return_url || configuration.return_url,
        merchant_id: merchant_id || configuration.merchant_id,
        client_key: client_key || configuration.client_private_key.gsub('\\n', '\n'),
        service_pub: configuration.service_public_key,
        client_pub_key: client_pub_key || configuration.client_public_key,
        logger: configuration.logger
      )
    end
  end

  # Configuration class for CsobPaymentGateway
  # This class is used to store the configuration for the CsobPaymentGateway
  class Configuration
    attr_accessor :gateway_url, :return_url, :merchant_id, :client_private_key,
                  :service_public_key, :client_public_key

    attr_reader :logger

    def logger=(lambda)
      raise ArgumentError, 'The logger must be a lambda' unless lambda.is_a?(Proc)

      @logger = lambda
    end

    def initialize(hash = {})
      @gateway_url = hash[:gateway_url]
      @return_url = hash[:return_url]
      @merchant_id = hash[:merchant_id]
      @client_private_key = hash[:client_private_key]
      @service_public_key = hash[:service_public_key]
      @client_public_key = hash[:client_public_key]
      @logger = hash[:logger]
    end
  end
end
