# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/csob_pg/client'
require 'nokogiri'

module CsobPaymentGateway
  # rubocop:disable Metrics/ClassLength
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
      client = create_client
      response = client.echo

      assert_equal :OK, RESULT_CODES[response.resultCode]
    end

    # payment/process - https://github.com/csob/platebnibrana/wiki/Z%C3%A1kladn%C3%AD-metody#payment-process-operation
    def test_get_url_to_the_gateway
      client = create_client
      url = client.process(init_payment(Minitest.seed + 1))

      response = HttpClient.get url
      redirect = response['location']

      exp = 'https://iplatebnibrana.csob.cz/pay/shop.example.com/'

      assert_equal(exp, redirect[0...exp.length])
    end

    # payment/init with addition params
    # rubocop:disable Metrics/MethodLength
    def test_get_status_of_initialized_payment_with_additional_params
      client = create_client
      payment_no = init_payment(Minitest.seed + 2,
                                customer: {
                                  account: {
                                    orderHistory: 3,
                                    suspicious: false
                                  },
                                  login: {
                                    auth: 'guest'
                                  },
                                  name: 'John Doe', email: 'john.doe@example.com'
                                },
                                order: { billing: { address1: 'aaaa', city: 'bbb', zip: 'aaa', country: 'CZE' },
                                         type: 'purchase' },
                                customerId: '1234567890')

      response = client.status(payment_no)

      assert_equal :OK, RESULT_CODES[response.resultCode]
      assert_equal :payment_initialized, TRANSACTION_LIFECYCLE[response.paymentStatus]
    end
    # rubocop:enable Metrics/MethodLength

    # payment/status - https://github.com/csob/platebnibrana/wiki/Z%C3%A1kladn%C3%AD-metody#payment-status-operation
    def test_get_status_of_initialized_payment
      client = create_client
      payment_no = init_payment(Minitest.seed + 2)
      response = client.status(payment_no)

      assert_equal :OK, RESULT_CODES[response.resultCode]
      assert_equal :payment_initialized, TRANSACTION_LIFECYCLE[response.paymentStatus]
    end

    # gateway tests - payment actions
    def test_invalid_card_payment
      pay_no = init_payment Minitest.seed + 3
      response = process_payment pay_no, CARD_VISA_AUTH_FAILURE

      assert_equal :payment_method_error, RESULT_CODES[response.resultCode]
    end

    def test_reverse_pending_payment
      client = create_client
      pay_no = init_payment Minitest.seed + 4
      process_response = process_payment pay_no
      reverse_response = client.reverse(pay_no)

      assert_equal :OK, RESULT_CODES[process_response.resultCode], process_response.resultMessage
      assert_equal :OK, RESULT_CODES[reverse_response.resultCode], reverse_response.resultMessage
    end

    def test_close_message_works
      client = create_client
      pay_no = init_payment Minitest.seed + 5
      response = client.close(pay_no)
      # unable to induce valid state for closing
      assert_equal :payment_not_in_valid_state, RESULT_CODES[response.resultCode]
    end

    def test_refund_message_works
      client = create_client
      pay_no = init_payment Minitest.seed + 6
      response = client.refund(pay_no)
      # unable to induce valid state for refund
      assert_equal :payment_not_in_valid_state, RESULT_CODES[response.resultCode]
    end

    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/MethodLength
    def process_payment(pay_no, cardnumber = CARD_VISA_AUTH_SUCCESS)
      client = create_client
      url = client.process(pay_no)

      response = HttpClient.get url
      id = response['location'].split('/').last
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

      3.times do
        break if client.status(pay_no).paymentStatus == 7

        sleep(0.25)
      end

      payment = client.status(pay_no)
      Message::GeneralResponse.new({
                                     payId: payment.payId,
                                     dttm: payment.dttm,
                                     resultCode: payment.resultCode,
                                     resultMessage: payment.resultMessage,
                                     paymentStatus: payment.paymentStatus,
                                     paymentStatusMessage: payment.paymentStatusMessage,
                                     authCode: payment.authCode
                                   })
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/MethodLength

    def init_payment(order_no, **options)
      client = create_client
      item = Message::Item.new name: 'RailsConf ', quantity: 1, amount: 2000, description: ' RailsConf'
      response = client.init(order_no: order_no.to_s, total_amount: 2000, items: [item], **options)

      assert_equal :OK, RESULT_CODES[response.resultCode], response.resultMessage
      assert_predicate response, :ok?
      assert_equal :payment_initialized, TRANSACTION_LIFECYCLE[response.paymentStatus]
      response.payId
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
  # rubocop:enable Metrics/ClassLength
end
