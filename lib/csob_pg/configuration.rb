require 'dry-struct'
require 'yaml'
require 'erb'
require_relative 'client'

module CsobPaymentGateway
  Types = Dry.Types()

  class << self
    def configure
      yield(configuration)
    end

    def configuration
      @configuration ||= Configuration.new(
        gateway_url: gateway_url,
        return_url: ENV['CSOB_RETURN_URL'] || '',
        merchant_id: ENV['CSOB_MERCHANT_ID'] || '',
        client_private_key: ENV['CSOB_CLIENT_PRIVATE_KEY'] || '',
        service_public_key: ENV['CSOB_SERVICE_PUBLIC_KEY'] || '',
        client_public_key: ENV['CSOB_CLIENT_PUBLIC_KEY'],
        logger: nil
      )
    end

    def client
      @client ||= create_client
    end

    def gateway_url
      environment = (ENV['CSOB_ENVIRONMENT'] || :production).to_sym
      version = (ENV['CSOB_VERSION'] || '1.9').to_s

      base_url = environment == :production ? "https://api.platebnibrana.csob.cz" : "https://iapi.iplatebnibrana.csob.cz"
      base_url += case version.to_s
      when '1.8'
        '/api/v1.8'
      when '1.9'
        '/api/v1.9'
      else
        raise "Unsupported API version"
      end
    end

    def create_client
      Client.new(
        configuration.gateway_url,
        configuration.return_url,
        configuration.merchant_id,
        configuration.client_private_key.gsub('\\n', '\n'),
        configuration.service_public_key,
        configuration.client_public_key,
        configuration.logger
      )
    end
  end

  class Configuration < Dry::Struct
    attribute :gateway_url, Types::String
    attribute :return_url, Types::String
    attribute :merchant_id, Types::String
    attribute :client_private_key, Types::String
    attribute :service_public_key, Types::String
    attribute :client_public_key, Types::String.optional
    attribute :logger, Types.Instance(Proc).optional

    attr_writer :gateway_url, :return_url, :merchant_id, :client_private_key, :service_public_key, :client_public_key

    def initialize(attributes = {})
      @logger = nil
      super(attributes)
    end

    def logger=(lambda)
      raise ArgumentError, "The key_name must be a lambda" unless lambda.is_a?(Proc)
      @logger = lambda
    end
  end
end
