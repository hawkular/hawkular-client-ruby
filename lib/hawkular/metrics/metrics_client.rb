
require 'hawkular/base_client'
require 'json'
require 'rest-client'
require 'English'

require 'hawkular/metrics/types'
require 'hawkular/metrics/tenant_api'
require 'hawkular/metrics/metric_api'

# Metrics module provides access to Hawkular Metrics REST API
# @see http://www.hawkular.org/docs/rest/rest-metrics.html Hawkular Metrics REST API Documentation
# @example Create Hawkular-Metrics client and start pushing some metric data
#  # create client instance
#  client = Hawkular::Metrics::Client::new("http://server","username",
#                "password",{"tenant" => "your tenant ID"})
#  # push gauge metric data for metric called "myGauge" (no need to create metric definition
#  # unless you wish to specify data retention)
#  client.gauges.push_data("myGauge", {:value => 3.1415925})
module Hawkular::Metrics
  class Client < Hawkular::BaseClient
    # @return [Tenants] access tenants API
    attr_reader :tenants
    # @return [Counters] access counters API
    attr_reader :counters
    # @return [Gauges] access gauges API
    attr_reader :gauges
    # @return [Availability] access counters API
    attr_reader :avail

    # @return [boolean] if it's using the legacy API or not
    attr_reader :legacy_api

    def check_version
      version_status_hash = fetch_version_and_status
      fail_version_msg = 'Unable to determine implementation version for metrics'
      fail fail_version_msg if version_status_hash['Implementation-Version'].nil?
      version = version_status_hash['Implementation-Version']
      major, minor = version.scan(/\d+/).map(&:to_i)
      fail fail_version_msg if major.nil? || minor.nil?
      @legacy_api = (major == 0 && minor < 16)
    end

    # Construct a new Hawkular Metrics client class.
    # optional parameters
    # @param entrypoint [String] Base url of the Hawkular (metrics) server
    # @param credentials Hash of username, password, token(optional)
    # @param options [Hash{String=>String}] client options
    # @example initialize with Hawkular-tenant option
    #   Hawkular::Metrics::Client::new("http://server",
    #     {username:"username",password:"password"},
    #                          {"tenant" => "your tenant ID"})
    #
    def initialize(entrypoint,
                   credentials = {},
                   options = {})
      entrypoint = normalize_entrypoint_url entrypoint, 'hawkular/metrics'
      super(entrypoint, credentials, options)
      check_version
      @tenants = Client::Tenants.new self
      @counters = Client::Counters.new self
      @gauges = Client::Gauges.new self
      @avail = Client::Availability.new self
    end
  end
end
