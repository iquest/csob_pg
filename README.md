# csob_pg

Implementation of a client to communicate with the payment gateway operated by ČSOB (Czechoslovak Trade Bank), API v1.9. [https://github.com/csob/platebnibrana/wiki](https://github.com/csob/platebnibrana/wiki)

## Description

This gem provides a Ruby client for interacting with the ČSOB payment gateway. It supports the API v1.9 and allows you to process online payments, manage transactions, and retrieve payment information.

## Features

*   Implements the ČSOB payment gateway API v1.9
*   Supports various payment methods
*   Provides a simple and intuitive interface for interacting with the gateway
*   Includes request and response message definitions
*   Supports configuration options for customizing the client

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'csob_pg'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install csob_pg
```

## Usage

```ruby
require 'csob_pg'

# Configure the client
CsobPaymentGateway.configure do |config|
  config.return_url = 'https://your-eshop.com/payment/success'
  config.merchant_id = 'your_merchant_id'
  config.client_private_key = '-----BEGIN RSA PRIVATE KEY-----xxxxx-----END RSA PRIVATE KEY-----'
  config.service_public_key = "-----BEGIN PUBLIC KEY-----xxxxx-----END PUBLIC KEY-----"
  # config.logger = -> { Logger.new(STDOUT) } # Optional, use for debugging
end

# Or by ENV variables
CSOB_RETURN_URL
CSOB_MERCHANT_ID
CSOB_CLIENT_PRIVATE_KEY
CSOB_SERVICE_PUBLIC_KEY

# Gateway config variables
CSOB_ENVIRONMENT = 'production' # or 'test'
CSOB_VERSION = '1.9' # API version, supported: 1.9, 1.8

# Create a new payment
client = CsobPaymentGateway.client
item = CsobPaymentGateway::Message::Item.new(
    name: "Fee",
    quantity: 1,
    amount: amount,
    description: "Payment for service"
  )

payment = client.init(order_number_string, amount, "CZK", item, "CZ")

# id of the payment
pay_id = payment.payId
payment = client.process(pay_id)
```

## Configuration

You can configure the gem using the `CsobPaymentGateway.configure` method. Available options are:

*   `return_url`: The URL to which the user will be redirected after payment.
*   `merchant_id`: Your merchant ID.
*   `client_private_key`: Your private key for signing requests.
*   `service_public_key`: The public key of the ČSOB payment gateway for verifying responses.

Example:

```ruby
  CsobPaymentGateway.configure do |config|
    config.return_url = ENV['CSOB_RETURN_URL']
    config.merchant_id = ENV['CSOB_MERCHANT_ID']
    config.client_private_key = ENV['CSOB_CLIENT_PRIVATE_KEY']
    config.service_public_key = ENV['CSOB_SERVICE_PUBLIC_KEY']
  end
```

## Contributing

Bug reports and pull requests are welcome on GitHub at [http://github.com/iquest/csob_pg/](http://github.com/iquest/csob_pg/).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Authors

*   iQuest s.r.o. - [https://www.iquest.cz](https://www.iquest.cz)

## Dependencies

*   rest-client ~> 2
*   dry-struct ~> 1

## Development Dependencies

*   nokogiri ~> 1
*   dotenv ~> 2