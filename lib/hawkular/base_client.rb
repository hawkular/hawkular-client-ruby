require 'base64'
require 'addressable/uri'
require 'hawkular/hawkular_client_utils'

module Hawkular
  # This is the base functionality for all the clients,
  # that inherit from it. You should not directly use it,
  # but through the more specialized clients.
  class BaseClient
    include HawkularUtilsMixin

    # @!visibility private
    attr_reader :credentials, :entrypoint, :options
    # @return [Tenants] access tenants API
    attr_reader :tenants

    def initialize(entrypoint = nil,
                   credentials = {},
                   options = {})
      @entrypoint = entrypoint
      @credentials = {
        username: nil,
        password: nil,
        token: nil
      }.merge(credentials)
      @options = {
        tenant: nil,
        ssl_ca_file: nil,
        verify_ssl: OpenSSL::SSL::VERIFY_PEER,
        ssl_client_cert: nil,
        ssl_client_key: nil,
        http_proxy_uri: nil,
        headers: {}
      }.merge(options)

      fail 'You need to provide an entrypoint' if entrypoint.nil?
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
      options[:ssl_ca_file] = @options[:ssl_ca_file]
      options[:verify_ssl] = @options[:verify_ssl]
      options[:ssl_client_cert] = @options[:ssl_client_cert]
      options[:ssl_client_key] = @options[:ssl_client_key]
      options[:proxy] = @options[:http_proxy_uri]
      options[:user] = @credentials[:username]
      options[:password] = @credentials[:password]
      # strip @endpoint in case suburl is absolute
      suburl = suburl[@entrypoint.length, suburl.length] if suburl.match(/^http/)
      RestClient::Resource.new(@entrypoint, options)[suburl]
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

    # Encode the passed credentials (username/password) into a base64
    # representation that can be used to generate a Http-Authentication header
    # @param credentials [Hash{:username,:password}]
    # @return [String] Base64 encoded result
    def base_64_credentials(credentials = {})
      creds = credentials.empty? ? @credentials : credentials

      encoded = Base64.encode64(creds[:username] + ':' + creds[:password])
      encoded.rstrip!
    end

    # Generate a query string from the passed hash, starting with '?'
    # Values may be an array, in which case the array values are joined together by `,`.
    # @param params [Hash] key-values pairs
    # @return [String] complete query string to append to a base url, '' if no valid params
    def generate_query_params(params = {})
      params = params.select { |_k, v| !(v.nil? || ((v.instance_of? Array) && v.empty?)) }
      return '' if params.empty?

      params.inject('?') do |ret, (k, v)|
        ret += '&' unless ret == '?'
        part = (v.instance_of? Array) ? "#{k}=#{v.join(',')}" : "#{k}=#{v}"
        ret + hawk_escape(part)
      end
    end

    # Specialized exception to be thrown
    # when the interaction with Hawkular fails
    class HawkularException < StandardError
      def initialize(message, status_code = 0)
        @message = message
        @status_code = status_code
        super(message)
      end

      attr_reader :message, :status_code
    end

    private

    def token_header
      @credentials[:token].nil? ? {} : { 'Authorization' => "Bearer #{@credentials[:token]}" }
    end

    def tenant_header
      headers = {}
      headers[:'Hawkular-Tenant'] = @options[:tenant] unless @options[:tenant].nil?
      headers
    end

    def handle_fault(f)
      if f.respond_to?(:http_body) && !f.http_body.nil?
        begin
          json_body = JSON.parse(f.http_body)
          fault_message = json_body['errorMsg'] || f.http_body
        rescue JSON::ParserError
          fault_message = f.http_body
        end
        fail HawkularException.new(fault_message, (f.respond_to?(:http_code) ? f.http_code : 0))
      else
        fail f
      end
    end
  end
end
