require_relative 'message'
require 'rest-client'
require 'json'


module CsobPaymentGateway
  class Client
    DEFAULT_PAY_OPERATION = 'payment'
    DEFAULT_PAY_METHOD = 'card'

    def initialize(url, return_url, merchant_id, client_key, service_pub)
      @url_base = url
      @return_url = return_url
      @merchant_id = merchant_id
      @client_key = OpenSSL::PKey::RSA.new(client_key)
      @service_pub = OpenSSL::PKey::RSA.new(service_pub)
    end

    def echo
      hash = {
        merchantId: @merchant_id,
        dttm: timestamp
      }
      echo = Message::Echo.new hash
      process_message echo, :post, Message::EchoResponse
    end

    def init(order_no, total_amount, currency, item, language)
      cart = [item]
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
      }
      init = Message::Init.new hash
      process_message init, :post, Message::GeneralResponse
    end

    def process_url(pay_id)
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
    rescue => e
      hash = {
        resultCode: 10000,
        resultMessage: e.message
      }
      Message::NullResponse.new hash
    end

    def get(message)
      url = @url_base + message.get_url(@client_key)
      RestClient.get url, { accept: :json}
    end

    def request(message, method)
      url = CGI.escapeHTML(@url_base + message.path)
      hash = message.signed(@client_key)
      case method
      when :post, :put
        RestClient.send method, url, hash.to_json, { content_type: :json, accept: :json }
      else
        raise "Method unimplemented: #{method}"
      end
    end

    def build_response(json, klass)
      hash = JSON.parse(json)
      transformed = hash.transform_keys { |k| k.to_sym }
      response = klass.new transformed
      raise "Response signature invalid" unless verify(response)
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