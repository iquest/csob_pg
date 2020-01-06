module CsobPaymentGateway
  ResultCodes = {
    0   => :OK,
    100 => :missing_parameter,
    110 => :invalid_parameter,
    120 => :merchant_blocked,
    130 => :session_expired,
    140 => :payment_not_found,
    150 => :payment_not_in_valid_state,
    160 => :payment_method_disabled,
    170 => :payment_method_unavailable,
    180 => :operation_not_allowed,
    190 => :payment_method_error,
    230 => :merchant_not_onboard_for_masterpass,
    240 => :masterpass_request_token_already_initialized,
    250 => :masterpass_request_token_does_not_exist,
    270 => :masterpass_cancelled_by_user,
    500 => :eet_rejected,
    600 => :mall_payment_declined,
    700 => :oneclick_template_not_found,
    710 => :oneclick_template_payment_expired,
    720 => :oneclick_template_card_expired,
    730 => :oneclick_template_customer_rejected,
    740 => :oneclick_template_payment_reversed,
    800 => :customer_not_found,
    810 => :customer_found_no_saved_card,
    820 => :customer_found_found_saved_card,
    900 => :internal_error,
    10000 => :application_error
  }.freeze

  TransactionLifecycle = {
    1 => :payment_initialized,
    2 => :payment_in_progress,
    3 => :payment_cancelled,
    4 => :payment_confirmed,
    5 => :payment_revoked,
    6 => :payment_declined,
    7 => :payment_pending,
    8 => :payment_cleared,
    9 => :repay_in_progress,
    10 => :payment_repaid
  }.freeze
end