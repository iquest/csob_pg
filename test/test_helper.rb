require 'minitest'
require 'byebug'
require 'openssl'
require 'pathname'
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
  TEST_URL = 'https://iapi.iplatebnibrana.csob.cz/api/v1.8/'
  RETURN_URL = 'localhost:3000/payment/return'

  CARD_VISA_AUTH_SUCCESS = 4125010001000208
  CARD_VISA_AUTH_FAILURE = 4140920001000209
  CARD_VISA_PARTIAL_AUTH = 4154610001000225
  CARD_VISA_BANK_FAILURE = 4154610001000217
  CARD_VISA_NO_3D_SECURE = 4154610001000209
  CARD_VISA_SERVICE_DOWN = 4154610001000308
  CARD_VISA_BAD_RESPONSE = 4154610001000407

  CVC_PAYMENT_DECLINED = 200
  CVC_SERVICE_DENIAL = 300
  CVC_CARD_BLOCKED = 400
  CVC_TECHNICAL_FAILURE = 500

  BANK_PUB_STRING = <<-EOPUB
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuo0GzBCQMl1wDJJrJHTQ
ykGlh2Kon7QfQjKVTPv7fPIVE8PhHeJueWBfydqTQKVeIVMB9VAUYlaPjwFhAuJ6
zqoaCG9m+q81L7CehsQThntxacOPwRd4SSyS5o+kPzTIFji0Z3c8s6pYJJoF+YfE
atCWRW2frgrgbHbl+84AOvItt7NReYz1z4P7J+Uv4UbifFHVP7oIEh+5CJSj6puv
jHh1QHrzE+dTaoKDhtOfSkTTelHqod/hUt4QIcHai6I8X/R5nEv3y40MWoi1FxbQ
6IgtVMloneN0XaHR5U88eMeKJJyqR859I4xfun6Z6RyfyaIl5Ph3f2daeMeENPUR
BQIDAQAB
-----END PUBLIC KEY-----
  EOPUB

  CLIENT_PUB_STRING = <<-EOPUB
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyRVmlsFqtRHbc+J0UizW
21+TjGitox4eZuNCvf8WuFGkJ5Ulj6Tx2EsKGIS/LKi4Fn//HSu3d8uMAVVE2eDo
cDDlojpvkOzgxcsyapBsfryxrCsG9zxKglKF19A8BTmoe1ll4kUvVuH05pTEkb9M
bsXL68nnUpP7AtcDKxlhH7hh5UgIT0GbLU9PkGdLugUDsy28rovz/jx/CC5CLS7X
EF6S4z7t8BrFGM2sFM0JXwXGw2xZVUw5c8G230c5uDhu0zNf5RHpLOmZqQ7IG+rM
IMU4Vwsht9p6ei+fiSyFpEDJBsA80Lh4ZLaoe3B80JDW6ZsH2ulEoa6Q1bSBXOTk
UwIDAQAB
-----END PUBLIC KEY-----
  EOPUB

  BANK_PUB = OpenSSL::PKey::RSA.new(BANK_PUB_STRING)
  CLIENT_PUB = OpenSSL::PKey::RSA.new(CLIENT_PUB_STRING)

  def self.symbolize_keys hsh
    hsh.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
  end

  def self.init_example
    {
      merchantId: "012345",
      orderNo: "5547",
      dttm: "20190925131559",
      payOperation: "payment",
      payMethod: "card",
      totalAmount: 1789600,
      currency: "CZK",
      closePayment: true,
      returnUrl: "https://vasobchod.cz/gateway-return",
      returnMethod: "POST",
      cart: [
        {
          name: "Nákup: vasobchod.cz",
          quantity: 1,
          amount: 1789600,
          description: "Lenovo ThinkPad Edge E540"
        },
        {
          name: "Poštovné",
          quantity: 1,
          amount: 0,
          description: "Doprava PPL"
        }
      ],
      merchantData: "md",
      language: "CZ"
    }
  end

  def self.general_example
    {
      merchantId:"012345",
      payId:"d165e3c4b624fBD",
      dttm:"20190925131559",
      signature:"base64-encoded-request-signature"
    }
  end

  def self.general_response
    hash = {
      payId:"d165e3c4b624fBD",
      dttm:"20190925131559",
      resultCode: 0,
      resultMessage:"OK",
      paymentStatus: 5,
    }
    to_sign = [hash[:payId], hash[:dttm], hash[:resultCode], hash[:resultMessage], hash[:paymentStatus]].join(Message::SEP)
    signature = Message::Signable.sign_encode_string to_sign, client_key
    hash[:signature] = signature
    hash
  end

end

def get_client
  CsobPaymentGateway.client
  #Client.new TEST_URL, CLIENT_ID, CLIENT_KEY_STRING, BANK_PUB_STRING
end

def client_key
  get_client.instance_variable_get(:@client_key)
end
