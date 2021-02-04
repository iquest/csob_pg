require_relative 'test_helper'
require_relative '../lib/csob_pg/client'
require 'nokogiri'

module CsobPaymentGateway
  ID_UP_FROM = 10005

  class ClientTest < Minitest::Test
    def test_sign_verify_process_works
      str = "ABCD"
      encoded = Message::Signable.sign_string str, client_key
      verified = Message::Verifiable.verify_string encoded, str, CLIENT_PUB
      assert verified
    end

    def test_sign_verify_process_works_for_encoded_strings
      str = "ABCD"
      encoded = Message::Signable.sign_encode_string str, client_key
      verified = Message::Verifiable.decode_verify_string encoded, str, CLIENT_PUB
      assert verified
    end

    def test_create_and_sign_init_message
      example = CsobPaymentGateway.init_example
      message = Message::Init.new example
      signature = message.signed(client_key)[:signature]
      assert(Message::Verifiable.decode_verify_string(signature, message.to_s, CLIENT_PUB))
    end

    def test_verify_example_response
      example = CsobPaymentGateway.general_response
      response = Message::GeneralResponse.new example
      assert(response.verify(CLIENT_PUB))
    end

    def test_echo_message_works
      c = get_client
      r = c.echo
      assert_equal :OK, ResultCodes[r.resultCode]
    end

    def test_get_url_to_the_gateway
      c = get_client
      url = c.process_url(init_payment ID_UP_FROM + 1)

      redirect = RestClient.get url
      exp = "https://iplatebnibrana.csob.cz/pay/shop.example.com/"
      assert_equal(exp, redirect.request.url[0...exp.length])
    end

    def test_get_status_of_initialized_payment
      c = get_client

      r = c.status(init_payment ID_UP_FROM + 2)
      assert_equal :OK, ResultCodes[r.resultCode]
      assert_equal :payment_initialized, TransactionLifecycle[r.paymentStatus]
    end

    def test_invalid_card_payment
      c = get_client
      pay_no = init_payment ID_UP_FROM + 3
      r = process_payment pay_no, CARD_VISA_AUTH_FAILURE
      assert_equal :internal_error, ResultCodes[r.resultCode]
    end

    def test_reverse_pending_payment
      c = get_client
      pay_no = init_payment ID_UP_FROM + 4
      r1 = process_payment pay_no
      r2 = c.reverse(pay_no)
      assert_equal :OK, ResultCodes[r1.resultCode], r1.resultMessage
      assert_equal :OK, ResultCodes[r2.resultCode], r2.resultMessage
    end

    def test_close_message_works
      c = get_client
      pay_no = init_payment ID_UP_FROM + 5
      r = c.close(pay_no)
      # unable to induce valid state for closing
      assert_equal :payment_not_in_valid_state, ResultCodes[r.resultCode]
    end

    def test_refund_message_works
      c = get_client
      pay_no = init_payment ID_UP_FROM + 6
      r = c.refund(pay_no)
      # unable to induce valid state for refund
      assert_equal :payment_not_in_valid_state, ResultCodes[r.resultCode]
    end

    def process_payment(pay_no, cardnumber = CARD_VISA_AUTH_SUCCESS)
      c = get_client
      url = c.process_url(pay_no)

      redirect = RestClient.get url
      id = redirect.request.url.split("/").last
      process_url = "https://iplatebnibrana.csob.cz/pay/shop.example.com/#{id}/process.json"
      hash = {
        cardnumber: cardnumber,
        expiry: {
          month: 12,
          year: 2021
        },
        cvc: 353
      }

      response = post_json process_url, hash
      redirect = JSON.parse(response.body)["redirect"]
      response = follow_redirect redirect
      doc = Nokogiri::HTML.parse response.body
      form = doc.css("form")[0]
      action = form.attribute("action").value
      pa_res = form.css("input")[1].attribute("value").value
      md = form.css("input")[2].attribute("value").value
      redirect = {
        "url" => action,
        "vars" => {
          "PaRes" => pa_res,
          "MD" => md
        }
      }
      response = follow_redirect redirect
      (0..2).each do
        break if c.status(pay_no).paymentStatus == 7
        sleep(0.25)
      end
      location = response.instance_variable_get(:@header)['location'][0]
      response = get_location location
      doc = Nokogiri::HTML.parse(response.body)
      form = doc.css("form")[0]
      params = if form && form.xpath('//*[@name="payId"]').length > 0
        payId = form.xpath('//*[@name="payId"]')[0].attribute("value").value
        dttm = form.xpath('//*[@name="dttm"]')[0].attribute("value").value
        resultCode = form.xpath('//*[@name="resultCode"]')[0].attribute("value").value
        resultMessage = form.xpath('//*[@name="resultMessage"]')[0].attribute("value").value
        paymentStatus = form.xpath('//*[@name="paymentStatus"]')[0].attribute("value").value
        signature = form.xpath('//*[@name="signature"]')[0].attribute("value").value
        authCode = form.xpath('//*[@name="authCode"]')[0].attribute("value").value
        {
          payId: payId,
          dttm: dttm,
          resultCode: resultCode,
          resultMessage: resultMessage,
          paymentStatus: paymentStatus,
          signature: signature,
          authCode: authCode
        }
      else
        return_url = doc.css("a")[0].attribute('href').value
        CGI.parse(return_url.split('?').last).map do |k, v|
          [k.to_sym, v[0]]
        end.to_h
      end
      Message::GeneralResponse.new params
    end

    def init_payment(order_no)
      c = get_client
      item = Message::Item.new name: 'RailsConf', quantity: 1, amount: 2000, description: ' RailsConf'
      r = c.init order_no.to_s, 2000, 'CZK', item, 'CZ'
      assert_equal :OK, ResultCodes[r.resultCode], r.resultMessage
      assert r.ok?
      assert_equal :payment_initialized, TransactionLifecycle[r.paymentStatus]
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

