# frozen_string_literal: true

require_relative 'message'
require_relative 'http_client'
require 'json'

module CsobPaymentGateway
  # This class is used for creating the client
  class Client
    DEFAULT_PAY_OPERATION = 'payment'
    DEFAULT_PAY_METHOD = 'card'

    def initialize(url, return_url, merchant_id, client_key, service_pub, client_pub_key = nil, logger = nil)
      @url_base = url[-1] == '/' ? url : "#{url}/"
      @return_url = return_url
      @merchant_id = merchant_id
      @client_key = OpenSSL::PKey::RSA.new(client_key)
      @client_pub = client_pub_key ? OpenSSL::PKey::RSA.new(client_pub_key) : nil
      @service_pub = OpenSSL::PKey::RSA.new(service_pub)
      @logger = logger
    end

    def echo
      hash = {
        merchantId: @merchant_id,
        dttm: timestamp
      }
      echo = Message::Echo.new hash
      process_message echo, :post, Message::EchoResponse
    end

    def init(order_no:, total_amount:, currency: 'CZK', items:, language: 'CZ', **options)
      if items.length > 2
        raise ArgumentError, 'Max 2 items are allowed'
      end

      cart = items
      hash = {
        merchantId: @merchant_id,
        orderNo: order_no,
        dttm: timestamp,
        payOperation: DEFAULT_PAY_OPERATION,
        payMethod: DEFAULT_PAY_METHOD,
        totalAmount: total_amount,
        currency: currency,
        closePayment: true,
        returnUrl: @return_url,
        returnMethod: 'POST',
        cart: cart,
        language: language
      }.merge(options)
      init = Message::Init.new hash
      process_message init, :post, Message::GeneralResponse
    end

    def process(pay_id)
      hash = {
        merchantId: @merchant_id,
        payId: pay_id,
        dttm: timestamp
      }
      process = Message::Process.new hash
      @url_base + process.get_url(@client_key)
    end

    def status(pay_id)
      hash = {
        merchantId: @merchant_id,
        payId: pay_id,
        dttm: timestamp
      }
      status = Message::Status.new hash
      process_message status, :get, Message::GeneralResponse
    end

    def reverse(pay_id)
      hash = {
        merchantId: @merchant_id,
        payId: pay_id,
        dttm: timestamp
      }
      reverse = Message::Reverse.new hash
      process_message reverse, :put, Message::GeneralResponse
    end

    def close(pay_id)
      hash = {
        merchantId: @merchant_id,
        payId: pay_id,
        dttm: timestamp
      }
      close = Message::Close.new hash
      process_message close, :put, Message::GeneralResponse
    end

    def refund(pay_id)
      hash = {
        merchantId: @merchant_id,
        payId: pay_id,
        dttm: timestamp
      }
      refund = Message::Refund.new hash
      process_message refund, :put, Message::GeneralResponse
    end

    def process_message(message, method, response_klass)
      json = case method
             when :get
               get message
             else
               request message, method
             end
      build_response json, response_klass
    rescue StandardError => e
      message = e.message
      message = e.response.body if e.respond_to?(:response) && e.response
      hash = {
        resultCode: 10_000,
        resultMessage: message
      }
      Message::NullResponse.new hash
    end

    def get(message)
      url = @url_base + message.get_url(@client_key)

      @logger&.call&.debug do
        "Get URL: #{url}\n" \
          "Get: #{message}"
      end

      response = HttpClient.get(url, { accept: :json })
      @logger&.call&.debug do
        "Get response: #{response.body}"
      end
      response.body
    end

    def request(message, method)
      url = CGI.escapeHTML(@url_base + message.path)
      hash = message.signed(@client_key)

      @logger&.call&.debug do
        "Request URL: #{url}\n" \
          "Request: #{hash}"
      end

      case method
      when :post, :put
        response = HttpClient.execute(method: method, url: url, payload: hash.to_json,
                                      headers: { content_type: :json, accept: :json })

        @logger&.call&.debug do
          "Request response: #{response.body}"
        end

        response.body
      else
        raise "Method unimplemented: #{method}"
      end
    end

    def build_response(json, klass)
      hash = JSON.parse(json)
      transformed = hash.transform_keys(&:to_sym)
      @logger&.call&.debug do
        "build_response: #{transformed}, class: #{klass}"
      end
      response = klass.new transformed
    rescue StandardError => e
      @logger&.call&.error do
        "Error building response: #{e.message}"
      end

      return CsobPaymentGateway::Message::NullResponse.new(
        resultCode: transformed[:resultCode],
        resultMessage: transformed[:resultMessage]
      )

      raise 'Response signature invalid' unless verify(response)

      response
    end

    def verify(response)
      response.verify(@service_pub)
    end

    def timestamp
      Message.timestamp(DateTime.now)
    end
  end
end
