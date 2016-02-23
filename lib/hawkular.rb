require 'base64'
require 'addressable/uri'

module Hawkular
  module Metrics
  end

  # This is the base functionality for all the clients,
  # that inherit from it. You should not directly use it,
  # but through the more specialized clients.
  class BaseClient
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

      fail 'You need to provide an entrypoint' if entrypoint.nil?
    end

    def http_get(suburl, headers = {})
      res = rest_client(suburl).get(http_headers(headers))
      puts "#{res}\n" if ENV['HAWKULARCLIENT_LOG_RESPONSE']
      res.empty? ? {} : JSON.parse(res)
    rescue
      handle_fault $ERROR_INFO
    end

    # Escapes the passed url part. This is necessary,
    # as many ids inside Hawkular can contain characters
    # that are invalid for an url/uri.
    # The passed value is duplicated
    # @param [String] url_part Part of an url to be escaped
    # @return [String] escaped url_part as new string
    def hawk_escape(url_part)
      return url_part.to_s if url_part.is_a?(Numeric)

      sub_url = url_part.dup
      sub_url.gsub!('%', '%25')
      sub_url.gsub!(' ', '%20')
      sub_url.gsub!('[', '%5b')
      sub_url.gsub!(']', '%5d')
      sub_url.gsub!('|', '%7c')
      sub_url.gsub!('(', '%28')
      sub_url.gsub!(')', '%29')
      sub_url.gsub!('/', '%2f')
      sub_url
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

    # Encode the passed credentials (username/password) into a base64
    # representation that can be used to generate a Http-Authentication header
    # @param credentials [Hash{:username,:password}]
    # @return [String] Base64 encoded result
    def base_64_credentials(credentials = {})
      creds = credentials.empty? ? @credentials : credentials

      encoded = Base64.encode64(creds[:username] + ':' + creds[:password])
      encoded.rstrip!
    end

    # Generate a query string from the passed hash.
    # This string starts with a `?` if the hash is
    # not empty.
    # Values may be an array, in which case the array values are joined together by `,`.
    # @param param_hash [Hash] key-values pairs
    # @return [String] complete query string to append to a base url
    def generate_query_params(param_hash = {})
      return '' if param_hash.size == 0

      num = count_non_nil_values(param_hash)

      i = 0
      ret = ''
      ret = '?' if num > 0
      param_hash.each  do |k, v|
        next if not_suitable?(v)

        if v.instance_of? Array
          part = "#{k}=#{v.join(',')}"
        else
          part = "#{k}=#{v}"
        end

        ret += hawk_escape part

        i += 1
        ret += '&' if i < num
      end
      ret
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

    def not_suitable?(v)
      v.nil? || (v.instance_of? Array) && v.size == 0
    end

    def count_non_nil_values(param_hash)
      num = 0
      param_hash.each do |_k, v|
        num += 1 unless not_suitable?(v)
      end
      num
    end

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
        fail HawkularException.new(fault_message, (f.respond_to?(:http_code) ? f.http_code : 0))
      else
        fail f
      end
    end
  end
end
