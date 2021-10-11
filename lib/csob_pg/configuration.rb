require 'yaml'
require 'erb'
require_relative 'client'

module CsobPaymentGateway

  def self.client
    @client ||= create_client(code)
  end

  def self.create_client(code = nil)
    conf = configuration_from_rails(code)
    Client.new(
      conf.gateway_url,
      conf.return_url,
      conf.merchant_id,
      conf.client_private_key,
      conf.service_public_key
    )
  end

  def self.configuration(hash)
    gateway_url = hash['gateway_url']
    return_url = hash['return_url']
    merchant_id = hash['merchant_id']
    client_private_key = hash['client_private_key']
    service_public_key = hash['service_public_key']

    Configuration.new(
      gateway_url,
      return_url,
      merchant_id,
      client_private_key,
      service_public_key
    )
  end

  def self.configuration_from_yaml(path, env, code = nil)
    erb = ERB.new(File.read(path)).result
    erb.gsub!("\n", "\n\n")
    yaml = YAML.load(erb)
    if yaml[env].has_key?(code)
      configuration(yaml[env][code])
    elsif yaml[env].has_key?('gateway_url')
      configuration(yaml[env])
    else
      configuration(yaml[env].first)
    end
  end

  def self.configuration_from_rails(code = nil)
    path = ::Rails.root.join('config', 'csob.yml')
    env = ::Rails.env.to_s
    configuration_from_yaml(path, env, code) if File.exists?(path)
  end

  class Configuration
    attr_reader :gateway_url, :return_url, :merchant_id, :client_private_key, :service_public_key

    def initialize(
      gateway_url,
      return_url,
      merchant_id,
      client_private_key,
      service_public_key
    )
      @gateway_url = gateway_url
      @return_url = return_url
      @merchant_id = merchant_id
      @client_private_key = client_private_key
      @service_public_key = service_public_key
    end
  end
end