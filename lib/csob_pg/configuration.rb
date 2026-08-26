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
# Named gateways can be loaded from config/csob.yml (Rails) or any YAML path
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

    def client(code = nil, **args)
      @clients ||= {}
      @clients[code] ||= create_client(code, **args)
    end

    def create_client(code = nil, **args)
      return Client.new(**args) unless code

      conf = configuration_from_rails(code)
      raise ArgumentError, "No configuration found for gateway code '#{code}'" unless conf

      Client.new(**client_kwargs_from_configuration(conf), **args)
    end

    def client_kwargs_from_configuration(conf)
      {
        url: conf.gateway_url,
        return_url: conf.return_url,
        merchant_id: conf.merchant_id,
        client_key: conf.client_private_key.to_s.gsub('\\n', '\n'),
        service_pub: conf.service_public_key,
        client_pub_key: conf.client_public_key,
        logger: conf.logger
      }
    end

    def configuration_from_hash(hash)
      hash = hash.transform_keys(&:to_sym)
      Configuration.new(
        gateway_url: hash[:gateway_url],
        return_url: hash[:return_url],
        merchant_id: hash[:merchant_id],
        client_private_key: hash[:client_private_key],
        service_public_key: hash[:service_public_key],
        client_public_key: hash[:client_public_key],
        logger: hash[:logger]
      )
    end

    def configuration_from_yaml(path, env, code = nil)
      erb = ERB.new(File.read(path)).result
      erb.gsub!("\n", "\n\n")
      yaml = YAML.safe_load(erb, aliases: true)
      env_config = yaml[env.to_s] || yaml[env.to_sym]
      raise ArgumentError, "Environment '#{env}' not found in #{path}" unless env_config

      selected = select_gateway_config(env_config, code)
      configuration_from_hash(selected)
    end

    def select_gateway_config(env_config, code = nil)
      if code && (env_config.key?(code) || env_config.key?(code.to_s))
        env_config[code] || env_config[code.to_s]
      elsif env_config.key?('gateway_url') || env_config.key?(:gateway_url)
        env_config
      else
        env_config.values.first
      end
    end

    def configuration_from_rails(code = nil)
      return unless defined?(::Rails) && ::Rails.respond_to?(:root)

      path = ::Rails.root.join('config', 'csob.yml')
      return unless File.exist?(path)

      env = ::Rails.env.to_s
      configuration_from_yaml(path, env, code)
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
