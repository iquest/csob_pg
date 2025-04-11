# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/csob_pg/client'
require 'nokogiri'

module CsobPaymentGateway
  ID_UP_FROM = 10_005

  class ClientTest < Minitest::Test
    # basic tests - crypto
    def test_sign_verify_process_works
      str = 'ABCD'
      encoded = Message::Signable.sign_string str, client_key
      verified = Message::Verifiable.verify_string encoded, str, client_pub_key
      assert verified
    end

    def test_sign_verify_process_works_for_encoded_strings
      str = 'ABCD'
      encoded = Message::Signable.sign_encode_string str, client_key
      verified = Message::Verifiable.decode_verify_string encoded, str, client_pub_key
      assert verified
    end

    def test_create_and_sign_init_message
      example = CsobPaymentGateway.init_example
      message = Message::Init.new example
      signature = message.signed(client_key)[:signature]
      assert(Message::Verifiable.decode_verify_string(signature, message.to_s, client_pub_key))
    end

    def test_verify_example_response
      example = CsobPaymentGateway.general_response
      response = Message::GeneralResponse.new example
      assert(response.verify(client_pub_key))
    end

    # gateway tests
    # echo - https://github.com/csob/platebnibrana/wiki/Z%C3%A1kladn%C3%AD-metody#echo-operation
    def test_echo_message_works
      c = create_client
      r = c.echo
      assert_equal :OK, RESULT_CODES[r.resultCode]
    end

    # payment/process - https://github.com/csob/platebnibrana/wiki/Z%C3%A1kladn%C3%AD-metody#payment-process-operation
    def test_get_url_to_the_gateway
      c = create_client
      url = c.process(init_payment(ID_UP_FROM + 1))

      redirect = RestClient.get url
      exp = 'https://iplatebnibrana.csob.cz/pay/shop.example.com/'
      assert_equal(exp, redirect.request.url[0...exp.length])
    end

    # payment/status - https://github.com/csob/platebnibrana/wiki/Z%C3%A1kladn%C3%AD-metody#payment-status-operation
    def test_get_status_of_initialized_payment
      c = create_client

      r = c.status(init_payment(ID_UP_FROM + 2))
      assert_equal :OK, RESULT_CODES[r.resultCode]
      assert_equal :payment_initialized, TRANSACTION_LIFECYCLE[r.paymentStatus]
    end

    # gateway tests - payment actions
    def test_invalid_card_payment
      pay_no = init_payment ID_UP_FROM + 3
      r = process_payment pay_no, CARD_VISA_AUTH_FAILURE
      assert_equal :payment_method_error, RESULT_CODES[r.resultCode]
    end

    def test_reverse_pending_payment
      c = create_client
      pay_no = init_payment ID_UP_FROM + 4
      r1 = process_payment pay_no
      r2 = c.reverse(pay_no)
      assert_equal :OK, RESULT_CODES[r1.resultCode], r1.resultMessage
      assert_equal :OK, RESULT_CODES[r2.resultCode], r2.resultMessage
    end

    def test_close_message_works
      c = create_client
      pay_no = init_payment ID_UP_FROM + 5
      r = c.close(pay_no)
      # unable to induce valid state for closing
      assert_equal :payment_not_in_valid_state, RESULT_CODES[r.resultCode]
    end

    def test_refund_message_works
      c = create_client
      pay_no = init_payment ID_UP_FROM + 6
      r = c.refund(pay_no)
      # unable to induce valid state for refund
      assert_equal :payment_not_in_valid_state, RESULT_CODES[r.resultCode]
    end

    def process_payment(pay_no, cardnumber = CARD_VISA_AUTH_SUCCESS)
      c = create_client
      url = c.process(pay_no)

      redirect = RestClient.get url
      id = redirect.request.url.split('/').last
      process_url = "https://iplatebnibrana.csob.cz/pay/shop.example.com/#{id}/process.json"
      hash = {
        cardnumber: cardnumber,
        expiry: {
          month: 12,
          year: 2031
        },
        cvc: 353
      }

      response = post_json process_url, hash
      body = JSON.parse(response.body)

      if body['error']
        error = body['error']
        return Message::ErrorResponse.new({
                                            type: error['type'],
                                            resultCode: 190,
                                            resultMessage: error['html']
                                          })
      end
      redirect = body['redirect']
      response = follow_redirect redirect
      doc = Nokogiri::HTML.parse response.body

      form = doc.css('form')[0]
      action = form.attribute('action').value
      pa_res = form.css('[name="cardnumber"]').attribute('value').value
      md = form.css('input')[2].attribute('value').value
      redirect = {
        'url' => action,
        'vars' => {
          'PaRes' => pa_res,
          'MD' => md
        }
      }
      response = follow_redirect redirect
      3.times do
        break if c.status(pay_no).paymentStatus == 7

        sleep(0.25)
      end
      location = response.instance_variable_get(:@header)['location'][0]
      response = get_location location
      doc = Nokogiri::HTML.parse(response.body)
      form = doc.css('form')[0]
      params = if form && form.xpath('//*[@name="payId"]').length.positive?
                 pay_id = form.xpath('//*[@name="payId"]')[0].attribute('value').value
                 dttm = form.xpath('//*[@name="dttm"]')[0].attribute('value').value
                 result_code = form.xpath('//*[@name="resultCode"]')[0].attribute('value').value
                 result_message = form.xpath('//*[@name="resultMessage"]')[0].attribute('value').value
                 payment_status = form.xpath('//*[@name="paymentStatus"]')[0].attribute('value').value
                 signature = form.xpath('//*[@name="signature"]')[0].attribute('value').value
                 auth_code = form.xpath('//*[@name="authCode"]')[0].attribute('value').value
                 {
                   payId: pay_id,
                   dttm: dttm,
                   resultCode: result_code,
                   resultMessage: result_message,
                   paymentStatus: payment_status,
                   signature: signature,
                   authCode: auth_code
                 }
               else
                 return_url = doc.css('a')[0].attribute('href').value
                 CGI.parse(return_url.split('?').last).map do |k, v|
                   [k.to_sym, v[0]]
                 end.to_h
               end
      Message::GeneralResponse.new params
    end

    def init_payment(order_no)
      c = create_client
      item = Message::Item.new name: 'RailsConf ', quantity: 1, amount: 2000, description: ' RailsConf'
      r = c.init order_no.to_s, 2000, 'CZK', item, 'CZ'
      assert_equal :OK, RESULT_CODES[r.resultCode], r.resultMessage
      assert r.ok?
      assert_equal :payment_initialized, TRANSACTION_LIFECYCLE[r.paymentStatus]
      r.payId
    end

    def get_location(uri_as_string)
      uri = URI(uri_as_string)
      request = Net::HTTP::Get.new(uri.path)
      http = Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl = true
      http.request(request)
    end

    def post_json(uri_as_string, hash)
      uri = URI(uri_as_string)
      request = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
      request.body = hash.to_json
      http = Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl = true
      http.request(request)
    end

    def post_form(uri_as_string, hash)
      uri = URI(uri_as_string)
      Net::HTTP.post_form uri, hash
    end

    def follow_redirect(redirect)
      uri = URI(redirect['url'])
      post_form uri, redirect['vars']
    end
  end
end
