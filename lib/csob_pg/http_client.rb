# frozen_string_literal: true

require 'net/http'
require 'uri'

module CsobPaymentGateway
  # This class is used for creating the HTTP client
  # and sending the requests to the payment gateway
  # It uses the Net::HTTP library to send the requests
  class HttpClient
    class << self
      def get(url, headers = {})
        execute(method: :get, url: url, payload: nil, headers: headers)
      end

      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/PerceivedComplexity
      def execute(method:, url:, payload:, headers: {})
        logger = CsobPaymentGateway.configuration.logger
        logger&.call&.debug("HTTP #{method.upcase} request to #{url}")

        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')

        request_class = case method
                        when :get
                          Net::HTTP::Get
                        when :post
                          Net::HTTP::Post
                        when :put
                          Net::HTTP::Put
                        else
                          raise ArgumentError, "Unsupported HTTP method: #{method}"
                        end

        request = request_class.new(uri.request_uri)
        headers.each { |key, value| request[key] = value }

        request['Content-Type'] ||= 'application/json'
        request['Accept'] ||= 'application/json'

        request.body = payload if payload

        http.request(request)
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Metrics/PerceivedComplexity
    end
  end
end
