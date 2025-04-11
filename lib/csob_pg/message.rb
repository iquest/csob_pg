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
        arr.join(SEP)
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
    OrderNo = Types::Strict::String.constrained(format: /^\d{1,10}$/)
    DtTm = Types::Strict::String.constrained(format: DATE_FORMAT)
    PayOperation = Types::String.enum('payment', 'oneclickPayment', 'customPayment')
    PayMethod = Types::String.enum('card')
    Currency = Types::String.enum('CZK', 'EUR', 'USD', 'GBP', 'HUF', 'PLN', 'HRK', 'RON', 'NOK', 'SEK')
    ReturnUrl = Types::Strict::String.constrained(max_size: 300)
    ReturnMethod = Types::String.enum('POST', 'GET')
    Base64 = Types::Strict::String.constrained(format: %r{^[A-Za-z0-9+/]+={,2}$})
    MerchantData = Base64.constrained(max_size: 255).meta(omittable: true)
    CustomerId = Types::Strict::String.constrained(max_size: 50).meta(omittable: true)
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
      attribute(:description, Types::Strict::String.constrained(max_size: 40).constructor(&:strip))
    end

    Dry::Types.register('cart.item', Item)

    # This class is used for cart
    class Cart
      extend Forwardable
      def_delegator :@arr, :length

      def initialize(arr)
        @arr = Types::Array.of('cart.item')[arr]
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
        arr = Types::Array.of('cart.item').call_unsafe(*args)
        new arr
      end

      def self.meta(*args)
        Types::Array.of('cart.item').meta(*args)
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
      attribute :totalAmount, 'integer'
      attribute :currency, Currency
      attribute :closePayment, Types::Bool
      attribute :returnUrl, ReturnUrl
      attribute :returnMethod, ReturnMethod
      attribute :cart, 'cart'
      attribute :merchantData, MerchantData
      attribute :customerId, CustomerId
      attribute :language, Language
    end

    # This class is used for all messages as a base class
    class GeneralMessage < AbstractMessage
      attribute :merchantId, 'string'
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
      attribute :amount, Types::Integer.meta(omittable: true)
    end

    # This class is used for refund request
    class Refund < GeneralMessage
      def path
        'payment/refund'
      end
      attribute :amount, Types::Integer.meta(omittable: true)
    end

    # This class is used for echo request
    class Echo < AbstractMessage
      def path
        'echo'
      end
      attribute :merchantId, 'string'
      attribute :dttm, DtTm
    end

    # This class is used for all responses as a base class
    class AbstractResponse < Dry::Struct
      include Verifiable
      attribute :signature, Base64.meta(omittable: true)
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
      attribute :paymentStatus, PaymentStatus.meta(omittable: true)
      attribute :paymentStatusMessage, PaymentStatusMessage.meta(omittable: true)
      attribute :authCode, Types::Strict::String.meta(omittable: true)
      attribute :customerCode, Types::Strict::String.meta(omittable: true).optional
      attribute :statusDetail, Types::Strict::String.meta(omittable: true).optional

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
      attribute :signature, Message::Base64
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
