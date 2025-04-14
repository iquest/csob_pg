# frozen_string_literal: true

require 'dry-struct'
require 'forwardable'
require 'base64'
require_relative 'constants'

module CsobPaymentGateway
  # This module is used for creating the message
  module Message
    SEP = '|'
    def self.timestamp(datetime)
      datetime.strftime('%Y%m%d%H%M%S')
    end

    # This module is used for creating the signature
    module SignaturePart
      KEYS_FOR_SKIP = [:paymentStatusMessage].freeze
      def to_s
        # We use attribute_names instead of attributes
        # in order to preserve predictable iteration order
        arr = self.class.attribute_names.each_with_object([]) do |name, array|
          next array if KEYS_FOR_SKIP.include?(name)

          value = attributes[name]
          unless value.nil?
            string = value.to_s
            array << string unless string.empty?
          end
        end
        out = arr.join(SEP)
        @logger&.call&.debug("Message: #{out}")
        out
      end
    end

    # This module is used for signing the message
    module Signable
      include SignaturePart

      def signed(private_key)
        hash = to_h
        hash[:signature] = sign(private_key)
        hash
      end

      def sign(key)
        Signable.sign_encode_string(to_s, key)
      end

      def self.sign_encode_string(string, key)
        signed = sign_string(string, key)
        ::Base64.encode64(signed).gsub("\n", '')
      end

      def self.sign_string(string, key)
        digest = OpenSSL::Digest.new('SHA256')
        key.sign(digest, string)
      end
    end

    # This module is used for verifying the signature
    module Verifiable
      include SignaturePart
      def verify(key)
        Verifiable.decode_verify_string signature, to_s, key
      end

      def self.decode_verify_string(encoded, expected, key)
        decoded = ::Base64.decode64(encoded)
        verify_string(decoded, expected, key)
      end

      def self.verify_string(string, expected, key)
        digest = OpenSSL::Digest.new('SHA256')
        key.verify(digest, string, expected)
      end
    end

    Types = Dry.Types()
    DATE_FORMAT = /^2[0-9]{3}(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])([01][0-9]|2[0-3])[0-5][0-9][0-5][0-9]$/
    DATE_ISO_FORMAT = /^2[0-9]{3}-0[1-9]-0[1-9]T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$/
    OrderNo = Types::Strict::String.constrained(format: /^\d{1,10}$/)
    DtTm = Types::Strict::String.constrained(format: DATE_FORMAT)
    PayOperation = Types::String.enum('payment', 'oneclickPayment', 'customPayment')
    PayMethod = Types::String.enum('card')
    Currency = Types::String.enum('CZK', 'EUR', 'USD', 'GBP', 'HUF', 'PLN', 'HRK', 'RON', 'NOK', 'SEK')
    ReturnUrl = Types::Strict::String.constrained(max_size: 300)
    ReturnMethod = Types::String.enum('POST', 'GET')
    Base64 = Types::Strict::String.constrained(format: %r{^[A-Za-z0-9+/]+={,2}$})
    MerchantData = Base64.constrained(max_size: 255)
    CustomerId = Types::Strict::String.constrained(max_size: 50)
    Language = Types::String.enum('CZ', 'EN', 'DE', 'FR', 'HU', 'IT', 'JP', 'PL', 'PT', 'RO', 'RU', 'SK', 'ES', 'TR',
                                  'VN', 'HR', 'SI')
    ResultCode = Types::Coercible::Integer.enum(*RESULT_CODES.keys)
    PayId = Types::Strict::String.constrained(size: 15)
    PaymentStatus = Types::Coercible::Integer.enum(*TRANSACTION_LIFECYCLE.keys)
    PaymentStatusMessage = Types::Coercible::Symbol.enum(*TRANSACTION_LIFECYCLE.values)

    # This class is used for cart item
    class Item < Dry::Struct
      include SignaturePart
      attribute(:name, Types::Strict::String.constrained(max_size: 20).constructor(&:strip))
      attribute :quantity, Types::Strict::Integer.constrained(gteq: 1)
      attribute :amount, Types::Strict::Integer.constrained(gteq: 0)
      attribute(:description?, Types::Strict::String.constrained(max_size: 40).constructor(&:strip))
    end

    class Address < Dry::Struct
      include SignaturePart
      attribute :address1, Types::Strict::String.constrained(max_size: 50).constructor(&:strip)
      attribute :address2?, Types::Strict::String.constrained(max_size: 50).constructor(&:strip)
      attribute :address3?, Types::Strict::String.constrained(max_size: 50).constructor(&:strip)
      attribute :city, Types::Strict::String.constrained(max_size: 50).constructor(&:strip)
      attribute :zip, Types::Strict::String.constrained(max_size: 16).constructor(&:strip)
      attribute :state?, Types::Strict::String.constrained(max_size: 50).constructor(&:strip) # 3166-2
      attribute :country, Types::Strict::String.constrained(format: /^[A-Z]{3}$/).constructor(&:strip) # 3166-1 alpha-3
    end

    class Account < Dry::Struct
      include SignaturePart
      attribute :createdAt?, Types::Strict::String.constrained(format: DATE_ISO_FORMAT).constructor(&:strip)
      attribute :changedAt?, Types::Strict::String.constrained(format: DATE_ISO_FORMAT).constructor(&:strip)
      attribute :changedPwdAt?, Types::Strict::String.constrained(format: DATE_ISO_FORMAT).constructor(&:strip)
      attribute :orderHistory?, Types::Strict::Integer.constrained(gteq: 0, lteq: 9999)
      attribute :paymentsDay?, Types::Strict::Integer.constrained(gteq: 0, lteq: 999)
      attribute :paymentsYear?, Types::Strict::Integer.constrained(gteq: 0, lteq: 999)
      attribute :oneclickAdds?, Types::Strict::Integer.constrained(gteq: 0, lteq: 999)
      attribute :suspicious?, Types::Strict::Bool
    end

    class GiftCard < Dry::Struct
      include SignaturePart
      attribute :totalAmount?, Types::Strict::Integer
      attribute :currency?, Types::Strict::String.enum('CZK', 'EUR', 'USD', 'GBP', 'HUF', 'PLN', 'RON', 'NOK', 'SEK')
      attribute :quantity?, Types::Strict::Integer.constrained(gteq: 1, lteq: 99)
    end

    class Login < Dry::Struct
      include SignaturePart
      attribute :auth?,
                Types::Strict::String.enum('guest', 'account', 'federated', 'issuer', 'thirdparty', 'fido',
                                           'fido_signed', 'api')
      attribute :authAt?, Types::Strict::String.constrained(format: DATE_ISO_FORMAT).constructor(&:strip)
      attribute :authData?, Types::Strict::String
    end

    class Customer < Dry::Struct
      include SignaturePart
      attribute :name?, Types::Strict::String.constrained(max_size: 45).constructor(&:strip)
      attribute :email?, Types::Strict::String.constrained(max_size: 100).constructor(&:strip)
      attribute :homePhone?, Types::Strict::String.constrained(format: /^\+[+0-9.]+\.[+0-9.]+$/).constructor(&:strip)
      attribute :workPhone?, Types::Strict::String.constrained(format: /^\+[+0-9.]+\.[+0-9.]+$/).constructor(&:strip)
      attribute :mobilePhone?,
                Types::Strict::String.constrained(format: /^\+[+0-9.]+\.[+0-9.]+$/).constructor(&:strip)
      attribute :account?, Account
      attribute :login?, Login
    end

    class Order < Dry::Struct
      include SignaturePart
      attribute :type?, Types::Strict::String.enum('purchase', 'balance', 'prepaid', 'cash', 'check')
      attribute :availability?,
                Types::Hash.map(Types::Strict::String.enum('now', 'preorder'),
                                Types::Strict::String.constrained(format: /^\d{4}-\d{2}-\d{2}$/))
      attribute :delivery?,
                Types::Strict::String.enum('shipping', 'shipping_verified', 'instore', 'digital', 'ticket', 'other')
      attribute :deliveryMode?, Types::Strict::Integer.enum(0, 1, 2, 3)
      attribute :deliveryEmail?, Types::Strict::String.constrained(max_size: 100).constructor(&:strip)
      attribute :nameMatch?, Types::Strict::Bool
      attribute :addressMatch?, Types::Strict::Bool
      attribute :billing?, Address
      attribute :shipping?, Address
      attribute :shippingAddedAt?, Types::Strict::String.constrained(format: DATE_ISO_FORMAT).constructor(&:strip)
      attribute :reorder?, Types::Strict::Bool
      attribute :giftcards?, GiftCard
    end

    Dry::Types.register('cart.item', Item)

    # This class is used for cart
    class Cart
      # FIXME: How to remove this dependency?
      extend Forwardable
      def_delegator :@arr, :length

      def initialize(arr)
        @arr = Types::Array('cart.item')[arr]
      end

      def to_s
        return '' if @arr.empty?

        arr = @arr.each_with_object([]) do |item, array|
          string = item.to_s
          array << string unless string.empty?
        end
        arr.join(SEP)
      end

      def self.call_unsafe(*args)
        arr = Types::Array('cart.item').call_unsafe(*args)
        new arr
      end

      def self.meta(*args)
        Types::Array('cart.item').meta(*args)
      end

      def to_ary
        @arr
      end
    end

    Dry::Types.register('cart', Cart)

    # This class is used as a base class for all messages
    class AbstractMessage < Dry::Struct
      include Signable
    end

    # This class is used for init request
    class Init < AbstractMessage
      def path
        'payment/init'
      end

      attribute :merchantId, Types::Strict::String
      attribute :orderNo, OrderNo
      attribute :dttm, DtTm
      attribute :payOperation, PayOperation
      attribute :payMethod, PayMethod
      attribute :totalAmount, Types::Strict::Integer
      attribute :currency, Currency
      attribute :closePayment, Types::Bool
      attribute :returnUrl, ReturnUrl
      attribute :returnMethod, ReturnMethod
      attribute :cart, Cart
      attribute :customer?, Customer
      attribute :order?, Order
      attribute :merchantData?, MerchantData
      attribute :customerId?, CustomerId
      attribute :language, Language
      attribute :ttlSec?, Types::Integer.constrained(gteq: 300, lteq: 1800)
      attribute :logoVersion?, Types::Integer
      attribute :colorSchemeVersion?, Types::Integer
      attribute :customExpiry?, DtTm
    end

    # This class is used for all messages as a base class
    class GeneralMessage < AbstractMessage
      attribute :merchantId, Types::Strict::String
      attribute :payId, PayId
      attribute :dttm, DtTm
    end

    # This module is used for creating request URL
    module GetRequest
      def get_url(key)
        signature = CGI.escape(sign(key))
        "#{path}/#{merchantId}/#{payId}/#{dttm}/#{signature}"
      end
    end

    # This class is used for process request
    class Process < GeneralMessage
      include GetRequest
      # sent from the browser
      def path
        'payment/process'
      end
    end

    # This class is used for status request
    class Status < GeneralMessage
      include GetRequest
      def path
        'payment/status'
      end
    end

    # This class is used for reverse request
    class Reverse < GeneralMessage
      def path
        'payment/reverse'
      end
    end

    # This class is used for close request
    class Close < GeneralMessage
      def path
        'payment/close'
      end
      attribute :amount?, Types::Integer
    end

    # This class is used for refund request
    class Refund < GeneralMessage
      def path
        'payment/refund'
      end
      attribute :amount?, Types::Integer
    end

    # This class is used for echo request
    class Echo < AbstractMessage
      def path
        'echo'
      end
      attribute :merchantId, Types::Strict::String
      attribute :dttm, DtTm
    end

    # This class is used for all responses as a base class
    class AbstractResponse < Dry::Struct
      include Verifiable
      attribute :signature?, Base64
      attr_reader :signature

      def initialize(hash)
        @signature = hash.delete(:signature)
        super
      end

      def ok?
        RESULT_CODES[resultCode] == :OK
      end
    end

    # This class is used for general response
    class GeneralResponse < AbstractResponse
      attribute :payId, PayId
      attribute :dttm, DtTm
      attribute :resultCode, ResultCode
      attribute :resultMessage, Types::Strict::String
      attribute :paymentStatus?, PaymentStatus
      attribute :paymentStatusMessage?, PaymentStatusMessage
      attribute :authCode?, Types::Strict::String
      attribute :customerCode?, Types::Strict::String
      attribute :statusDetail?, Types::Strict::String

      def initialize(hash)
        hash[:paymentStatusMessage] = TRANSACTION_LIFECYCLE[hash[:paymentStatus]] if hash[:paymentStatus]
        super
      end
    end

    # This class is used for error response
    class ErrorResponse < AbstractResponse
      attribute :type, Types::Strict::String
      attribute :resultCode, ResultCode
      attribute :resultMessage, Types::Strict::String
    end

    # This class is used for echo response
    class EchoResponse < AbstractResponse
      attribute :dttm, DtTm
      attribute :resultCode, ResultCode
      attribute :resultMessage, Types::Strict::String
    end

    # This class is used when the response is not a valid JSON
    # or when the response is not a valid CsobPaymentGateway response
    class NullResponse < Dry::Struct
      attribute :resultCode, ResultCode
      attribute :resultMessage, Types::Strict::String

      def ok?
        false
      end
    end
  end
end
