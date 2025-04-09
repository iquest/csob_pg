require_relative 'message'
require 'rest-client'
require 'json'


module CsobPaymentGateway
  class Client
    DEFAULT_PAY_OPERATION = 'payment'
    DEFAULT_PAY_METHOD = 'card'

    def initialize(url, return_url, merchant_id, client_key, service_pub, client_pub_key = nil, logger = nil)
      @url_base = url[-1] == '/' ? url : url + '/'
      @return_url = return_url
      @merchant_id = merchant_id
      @client_key = OpenSSL::PKey::RSA.new(client_key)
      @client_pub = client_pub_key ? OpenSSL::PKey::RSA.new(client_pub_key) : nil
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
      Rails.logger.info "CSOB: payment init for #{@merchant_id} order_no #{order_no}"
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
    rescue => e
      message = e.message
      message = e.response.body if e.respond_to?(:response) && e.response
      hash = {
        resultCode: 10000,
        resultMessage: message
      }
      Message::NullResponse.new hash
    end

    def get(message)
      url = @url_base + message.get_url(@client_key)
      response = RestClient.get url, { accept: :json }
      response.body
    end

    def request(message, method)
      url = CGI.escapeHTML(@url_base + message.path)
      hash = message.signed(@client_key)
      case method
      when :post, :put
        response = RestClient::Request.execute(method: method, url: url, payload: hash.to_json, headers: { content_type: :json, accept: :json })
        response.body
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