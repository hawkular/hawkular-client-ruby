

require 'json'
require 'rest-client'

module Hawkular
  # Metrics module provides access to Hawkular Metrics REST API
  # @see http://www.hawkular.org/docs/rest/rest-metrics.html Hawkular Metrics REST API Documentation
  # @example Create Hawkular-Metrics client and start pushing some metric data
  #  # create client instance
  #  client = Hawkular::Metrics::Client::new("http://server","username",
  #                "password",{"tenant" => "your tenant ID"})
  #  # push gauge metric data for metric called "myGauge" (no need to create metric definition
  #  # unless you wish to specify data retention)
  #  client.gauges.push_data("myGauge", {:value => 3.1415925})
  module Metrics
  end
end

require 'metrics/types'
require 'metrics/tenant_api'
require 'metrics/metric_api'

module Hawkular::Metrics
  class HawkularException < StandardError
    def initialize(message)
      @message = message
      super
    end

    attr_reader :message
  end

  class Client
    # @!visibility private
    attr_reader :credentials, :entrypoint, :options
    # @return [Tenants] access tenants API
    attr_reader :tenants
    # @return [Counters] access counters API
    attr_reader :counters
    # @return [Gauges] access gauges API
    attr_reader :gauges
    # @return [Availability] access counters API
    attr_reader :avail

    # Construct a new Hawkular Metrics client class.
    # optional parameters
    # @param entrypoint [String]
    # @param username [String]
    # @param password [String]
    # @param options [Hash{String=>String}] client options
    # @example initialize with Hawkular-tenant option
    #   Hawkular::Metrics::Client::new("http://server","username","password",
    #                          {"tenant" => "your tenant ID"})
    #
    def initialize(entrypoint = 'http://localhost:8080/hawkular/metrics',
                   credentials = {},
                   options = {})
      @entrypoint = entrypoint
      @credentials = {
        username: nil,
        password: nil,
        token:    nil
      }.merge(credentials)
      @options = {
        tenant: nil,
        ssl_ca_file: nil,
        verify_ssl: OpenSSL::SSL::VERIFY_PEER,
        ssl_client_cert: nil,
        ssl_client_key: nil,
        headers: {}
      }.merge(options)

      @tenants = Client::Tenants.new self
      @counters = Client::Counters.new self
      @gauges = Client::Gauges.new self
      @avail = Client::Availability.new self
    end

    def http_get(suburl, headers = {})
      res = rest_client(suburl).get(http_headers(headers))
      puts "#{res}\n" if ENV['HAWKULARCLIENT_LOG_RESPONSE']
      res.empty? ? {} : JSON.parse(res)
    rescue
      handle_fault $ERROR_INFO
    end

    def http_post(suburl, hash, headers = {})
      body = JSON.generate(hash)
      res = rest_client(suburl).post(body, http_headers(headers))
      puts "#{res}\n" if ENV['HAWKULARCLIENT_LOG_RESPONSE']
      res.empty? ? {} : JSON.parse(res)
    rescue
      handle_fault $ERROR_INFO
    end

    def http_put(suburl, hash, headers = {})
      body = JSON.generate(hash)
      res = rest_client(suburl).put(body, http_headers(headers))
      puts "#{res}\n" if ENV['HAWKULARCLIENT_LOG_RESPONSE']
      res.empty? ? {} : JSON.parse(res)
    rescue
      handle_fault $ERROR_INFO
    end

    def http_delete(suburl, headers = {})
      res = rest_client(suburl).delete(http_headers(headers))
      puts "#{res}\n" if ENV['HAWKULARCLIENT_LOG_RESPONSE']
      res.empty? ? {} : JSON.parse(res)
    rescue
      handle_fault $ERROR_INFO
    end

    # @!visibility private
    def rest_client(suburl)
      options[:timeout] = ENV['HAWKULARCLIENT_REST_TIMEOUT'] if ENV['HAWKULARCLIENT_REST_TIMEOUT']
      options[:ssl_ca_file]     = @options[:ssl_ca_file]
      options[:verify_ssl]      = @options[:verify_ssl]
      options[:ssl_client_cert] = @options[:ssl_client_cert]
      options[:ssl_client_key]  = @options[:ssl_client_key]
      options[:user]            = @credentials[:username]
      options[:password]        = @credentials[:password]
      # strip @endpoint in case suburl is absolute
      suburl = suburl[@entrypoint.length, suburl.length] if suburl.match(/^http/)
      RestClient::Resource.new(@entrypoint, options)[suburl]
    end

    # @!visibility private
    def base_url
      url = URI.parse(@entrypoint)
      "#{url.scheme}://#{url.host}:#{url.port}"
    end

    # @!visibility private
    def self.parse_response(response)
      JSON.parse(response)
    end

    # @!visibility private
    def http_headers(headers = {})
      {}.merge(tenant_header)
        .merge(token_header)
        .merge(@options[:headers])
        .merge(content_type: 'application/json',
               accept: 'application/json')
        .merge(headers)
    end

    # timestamp of current time
    # @return [Integer] timestamp
    def now
      Integer(Time.now.to_f * 1000)
    end

    private

    def token_header
      @credentials[:token].nil? ? {} : { 'Authorization' => "Bearer #{@credentials[:token]}" }
    end

    def tenant_header
      @options[:tenant].nil? ? {} : { :'Hawkular-Tenant' => @options[:tenant],
                                      'tenantId' => @options[:tenant] }
    end

    def handle_fault(f)
      if f.respond_to?(:http_body) && !f.http_body.nil?
        begin
          json_body = JSON.parse(f.http_body)
          fault_message = json_body['errorMsg'] || f.http_body
        rescue JSON::ParserError
          fault_message = f.http_body
        end
        fail HawkularException, fault_message
      else
        fail f
      end
    end
  end
end
