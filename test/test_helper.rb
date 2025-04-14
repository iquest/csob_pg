# frozen_string_literal: true

require 'minitest'
require 'byebug'
require 'openssl'
require 'pathname'
require 'dotenv'
require_relative '../lib/../lib/csob_pg/configuration'

module Rails
  def self.root
    dir = File.dirname(__FILE__)
    Pathname.new dir
  end

  def self.env
    :test
  end
end

module CsobPaymentGateway
  CARD_VISA_AUTH_SUCCESS = 4_000_007_000_010_006
  CARD_VISA_AUTH_FAILURE = 4_000_007_000_020_005
  CARD_VISA_PARTIAL_AUTH = 4_000_007_000_030_004
  # CARD_VISA_BANK_FAILURE = 4154610001000217
  # CARD_VISA_NO_3D_SECURE = 4154610001000209
  # CARD_VISA_SERVICE_DOWN = 4154610001000308
  # CARD_VISA_BAD_RESPONSE = 4154610001000407

  CVC_PAYMENT_DECLINED = 200
  CVC_SERVICE_DENIAL = 300
  CVC_CARD_BLOCKED = 400
  CVC_TECHNICAL_FAILURE = 500

  Dotenv.load('.env.test', '.env')

  def self.symbolize_keys(hsh)
    hsh.transform_keys(&:to_sym)
  end

  # rubocop:disable Metrics/MethodLength
  def self.init_example
    {
      merchantId: '012345',
      orderNo: '5547',
      dttm: '20190925131559',
      payOperation: 'payment',
      payMethod: 'card',
      totalAmount: 1_789_600,
      currency: 'CZK',
      closePayment: true,
      returnUrl: 'https://vasobchod.cz/gateway-return',
      returnMethod: 'POST',
      cart: [
        {
          name: 'Nákup: vasobchod.cz',
          quantity: 1,
          amount: 1_789_600,
          description: 'Lenovo ThinkPad Edge E540'
        },
        {
          name: 'Poštovné',
          quantity: 1,
          amount: 0,
          description: 'Doprava PPL'
        }
      ],
      merchantData: 'md',
      language: 'CZ'
    }
  end
  # rubocop:enable Metrics/MethodLength

  def self.general_example
    {
      merchantId: '012345',
      payId: 'd165e3c4b624fBD',
      dttm: '20190925131559',
      signature: 'base64-encoded-request-signature'
    }
  end

  # rubocop:disable Metrics/MethodLength
  def self.general_response
    hash = {
      payId: 'd165e3c4b624fBD',
      dttm: '20190925131559',
      resultCode: 0,
      resultMessage: 'OK',
      paymentStatus: 5
    }
    to_sign = [hash[:payId], hash[:dttm], hash[:resultCode], hash[:resultMessage],
               hash[:paymentStatus]].join(Message::SEP)
    signature = Message::Signable.sign_encode_string to_sign, client_key
    hash[:signature] = signature
    hash
  end
  # rubocop:enable Metrics/MethodLength
end

def create_client
  CsobPaymentGateway.configure do |config|
    config.return_url = ENV.fetch('RETURN_URL', nil)
    config.merchant_id = ENV.fetch('MERCHANT_ID', nil)
    config.client_private_key = ENV.fetch('CLIENT_PRIVATE_KEY', nil)
    config.service_public_key = ENV.fetch('SERVICE_PUBLIC_KEY', nil)
    config.client_public_key = ENV.fetch('CLIENT_PUBLIC_KEY', nil)
    # config.logger = -> { Logger.new(STDOUT) }
  end
  CsobPaymentGateway.client
end

def client_key
  create_client.instance_variable_get(:@client_key)
end

def client_pub_key
  create_client.instance_variable_get(:@client_pub)
end
