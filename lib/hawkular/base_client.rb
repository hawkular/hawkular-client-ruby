require 'base64'
require 'addressable/uri'

require 'hawkular/logger'
require 'hawkular/client_utils'

module Hawkular
  # This is the base functionality for all the clients,
  # that inherit from it. You should not directly use it,
  # but through the more specialized clients.
  class BaseClient
    include ClientUtils

    # @!visibility private
    attr_reader :credentials, :entrypoint, :options, :logger
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
        verify_ssl: OpenSSL::SSL::VERIFY_PEER,
        headers: {}
      }.merge(options)
      @tenant = @options.delete(:tenant)
      @admin_token = @options.delete(:admin_token)

      @logger = Hawkular::Logger.new

      fail 'You need to provide an entrypoint' if entrypoint.nil?
    end

    def http_get(suburl, headers = {})
      res = rest_client(suburl).get(http_headers(headers))

      logger.log(res)

      res.empty? ? {} : JSON.parse(res)
    rescue
      handle_fault $ERROR_INFO
    end

    def http_post(suburl, hash, headers = {})
      body = JSON.generate(hash)
      res = rest_client(suburl).post(body, http_headers(headers))

      logger.log(res)

      res.empty? ? {} : JSON.parse(res)
    rescue
      handle_fault $ERROR_INFO
    end

    def http_put(suburl, hash, headers = {})
      body = JSON.generate(hash)
      res = rest_client(suburl).put(body, http_headers(headers))

      logger.log(res)

      res.empty? ? {} : JSON.parse(res)
    rescue
      handle_fault $ERROR_INFO
    end

    def http_delete(suburl, headers = {})
      res = rest_client(suburl).delete(http_headers(headers))

      logger.log(res)

      res.empty? ? {} : JSON.parse(res)
    rescue
      handle_fault $ERROR_INFO
    end

    # @!visibility private
    def rest_client(suburl)
      opts = @options.dup
      opts[:timeout] ||= ENV['HAWKULARCLIENT_REST_TIMEOUT'] if ENV['HAWKULARCLIENT_REST_TIMEOUT']
      opts[:proxy] ||= opts.delete(:http_proxy_uri)
      opts[:user] = @credentials[:username]
      opts[:password] = @credentials[:password]
      # strip @endpoint in case suburl is absolute
      suburl = suburl[@entrypoint.length, suburl.length] if suburl.match(/^http/)
      RestClient::Resource.new(@entrypoint, opts)[suburl]
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

    # Generate a new url with the passed sufix path if the path is not already added
    # also, this function always remove the slash at the end of the URL, so if your entrypoint is
    # http://localhost/hawkular/inventory/ this function will return http://localhost/hawkular/inventory
    # to the URL
    # @param entrypoint [String] base path (URIs are also accepted)
    # @param suffix_path [String] sufix path to be added if it doesn't exist
    # @return [String] URL with path attached to it at the end
    def normalize_entrypoint_url(entrypoint, suffix_path)
      fail ArgumentError, 'suffix_path must not be empty' if suffix_path.empty?
      strip_path = suffix_path.gsub(%r{/$}, '')
      strip_path.nil? || suffix_path = strip_path
      strip_path = suffix_path.gsub(%r{^/}, '')
      strip_path.nil? || suffix_path = strip_path
      entrypoint = entrypoint.to_s
      strip_entrypoint = entrypoint.gsub(%r{/$}, '')
      strip_path.nil? && strip_entrypoint = entrypoint
      relative_path_rgx = Regexp.new("\/#{Regexp.quote(suffix_path)}(\/)*$")
      if relative_path_rgx.match(entrypoint)
        strip_entrypoint
      else
        "#{strip_entrypoint}/#{suffix_path}"
      end
    end

    # Generate a new url using the websocket scheme. It changes the current scheme to
    # 'ws' for 'http' and 'wss' for 'https' urls.
    # @param url [String|URI] url
    # @return [String] URL with the scheme changed to 'ws' or 'wss' depending on the current scheme.
    def url_with_websocket_scheme(url)
      url.to_s.sub(/^http(s?)/, 'ws\1')
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

    class HawkularConnectionException < HawkularException
    end

    def admin_header
      headers = {}
      headers[:'Hawkular-Admin-Token'] = @admin_token unless @admin_token.nil?
      headers
    end

    private

    def token_header
      @credentials[:token].nil? ? {} : { 'Authorization' => "Bearer #{@credentials[:token]}" }
    end

    def tenant_header
      headers = {}
      headers[:'Hawkular-Tenant'] = @tenant unless @tenant.nil?
      headers
    end

    # @!visibility private
    def connect_error(fault)
      if fault.is_a?(SocketError)
        HawkularConnectionException.new(fault.to_s)
      elsif [Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
             Errno::EADDRNOTAVAIL, Errno::ENETDOWN, Errno::ENETUNREACH,
             Errno::ETIMEDOUT].include?(fault.class)
        HawkularConnectionException.new(fault.to_s, fault.class::Errno)
      end
    end

    def handle_fault(f)
      http_code = (f.respond_to?(:http_code) ? f.http_code : 0)
      fail HawkularException.new('Unauthorized', http_code) if f.instance_of? RestClient::Unauthorized
      if f.respond_to?(:http_body) && !f.http_body.nil?
        begin
          json_body = JSON.parse(f.http_body)
          fault_message = json_body['errorMsg'] || f.http_body
        rescue JSON::ParserError
          fault_message = f.http_body
        end
        fail HawkularException.new(fault_message, http_code)
      elsif (connect_error_exception = connect_error(f))
        fail connect_error_exception
      else
        fail f
      end
    end
  end
end
