require_relative 'test_helper'
require_relative '../lib/csob_pg/message'


module CsobPaymentGateway
  class MessageTest < Minitest::Test
    def assert_good(arr, type)
      arr.all? do |string|
        assert_equal string, type[string]
      end
    end

    def assert_bad(string, type)
      e = assert_raises do
        type[string]
      end
      exp = "\"#{string}\" violates constraints"
      assert_equal(exp, e.message[0...exp.length])
    end

    def test_order_number_constraint_works
      assert_bad '01234567890', Message::OrderNo
      good = %w(0 01 0123 0123456789)
      assert_good good, Message::OrderNo
    end

    def test_date_format_constraint_works
      good = %w(20000101000000 20190209010101 20200311091010 20290415112222 20510722123737 20680929134545 20731030175151 29991131235959)
      assert_good good, Message::DtTm
      # year in the past
      assert_bad '19990622135501', Message::DtTm
      # year in too far in future
      assert_bad '30000622135501', Message::DtTm
      # month out of range
      assert_bad '20201322135501', Message::DtTm
      # day out of range
      assert_bad '20200732135501', Message::DtTm
      # hour out of range
      assert_bad '20200715245501', Message::DtTm
      # minute out of range
      assert_bad '20200715236001', Message::DtTm
      # second out of range
      assert_bad '20200715235960', Message::DtTm
    end

    def test_pay_operation_enum_constraint_works
      good = %w(payment oneclickPayment customPayment)
      assert_good good, Message::PayOperation
      assert_bad 'bogus', Message::PayOperation
    end

    def test_pay_method_enum_constraint_works
      good = %w(card)
      assert_good good, Message::PayMethod
      assert_bad 'bogus', Message::PayMethod
    end

    def test_currency_enum_constraint_works
      good = %w(CZK EUR USD GBP HUF PLN HRK RON NOK SEK)
      assert_good good, Message::Currency
      assert_bad 'XLF', Message::Currency
    end

    def test_language_enum_constraint_works
      good = %w(CZ EN DE FR HU IT JP PL PT RO RU SK ES TR VN HR SI)
      assert_good good, Message::Language
      assert_bad 'XY', Message::Language
    end

    def test_base64_constraint_works
      good = %w(ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvxyz0123456789/+==)
      assert_good good, Message::Base64
    end

    def test_merchant_data_constraint_works
      good = %w(ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvxyz0123456789/++=)
      assert_good good, Message::MerchantData
      too_long = good[0] * 4
      assert_equal(256, too_long.length)
      assert_bad too_long, Message::MerchantData
    end

    def test_response_from_json
      success = "{\"payId\":\"d165e3c4b624fBD\",\"dttm\":\"20190925131559\",\"resultCode\":0,\"resultMessage\":\"OK\",\"paymentStatus\":1,\"signature\":\"ABCD\"}"
      hash = CsobPaymentGateway.symbolize_keys(JSON.parse(success))
      m = Message::GeneralResponse.new hash
      assert_equal("d165e3c4b624fBD", m.payId)
      assert_equal("20190925131559", m.dttm)
      assert_equal(0, m.resultCode)
      assert_equal('OK', m.resultMessage)
      assert_equal(1, m.paymentStatus)
      assert_equal('ABCD', m.signature)
      assert_nil(m.authCode)
      assert_nil(m.customerCode)
      assert_nil(m.statusDetail)
    end

    def test_init_message_from_example
      example = CsobPaymentGateway.init_example
      m = Message::Init.new example
      assert_equal(example[:merchantId], m.merchantId)
      assert_equal(example[:orderNo], m.orderNo)
      assert_equal(2, m.cart.length)
      assert_equal('md', m.merchantData)
      assert_equal('CZ', m.language)
      string = m.to_s
      exp = "012345|5547|20190925131559|payment|card|1789600|CZK|true|"
      exp += "https://vasobchod.cz/gateway-return|POST|Nákup: vasobchod.cz|1|1789600|"
      exp += "Lenovo ThinkPad Edge E540|Poštovné|1|0|Doprava PPL|md|CZ"
      assert_equal(exp, string)
      h = m.to_hash
      assert_equal example, h
    end

    def test_integer_coercion_works_for_response
      data = {
        payId: "abcdefghijklmno",
        dttm: "20150101000000",
        resultCode: '0',
        resultMessage: "OK",
        paymentStatus: '7',
        signature: 'bogus+ignature'
      }
      msg = Message::GeneralResponse.new(data)
      assert msg.ok?
    end

    def test_ok_method_works
      r = Message::EchoResponse.new(
        dttm: "20200312213050",
        resultCode: 0,
        resultMessage: "OK",
        signature: 'bogus'
      )
      assert r.ok?
      r = Message::EchoResponse.new(
        dttm: "20200312213001",
        resultCode: 100,
        resultMessage: "Bad",
        signature: 'bogus'
      )
      refute r.ok?

      r = Message::GeneralResponse.new(
        payId: "abcdefghijklmno",
        dttm: "20200312213059",
        resultCode: 0,
        resultMessage: "OK",
        paymentStatus: 1,
        signature: 'bogus'
      )
      assert r.ok?

      r = Message::GeneralResponse.new(
        payId: "abcdefghijklmno",
        dttm: "20190209010101",
        resultCode: 110,
        resultMessage: "Bad",
        paymentStatus: 1,
        signature: 'bogus'
      )
      refute r.ok?

      r = Message::NullResponse.new(
        resultCode: 10000,
        resultMessage: "Bad"
      )
      refute r.ok?

    end
  end
end