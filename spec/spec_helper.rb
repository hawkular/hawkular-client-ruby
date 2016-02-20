require 'hawkular'
require 'metrics/metrics_client'
require 'inventory/inventory_api'
require 'tokens/tokens_api'
require 'alerts/alerts_api'
require 'rspec/core'
require 'rspec/mocks'
require 'socket'
require 'uri'
require 'yaml'
require 'coveralls'

Coveralls.wear!

module Hawkular::Metrics::RSpec
  def setup_client(options = {})
    credentials = {
      username: config['user'],
      password: config['password']
    }
    @client = Hawkular::Metrics::Client.new(config['url'],
                                            credentials, options)
  end

  def setup_client_new_tenant(_options = {})
    setup_client
    @tenant = 'vcr-test-tenant-123'
    # @client.tenants.create(@tenant)
    setup_client(tenant: @tenant)
  end

  def config
    @config ||= YAML.load(
      File.read(File.expand_path('endpoint.yml', File.dirname(__FILE__)))
    )
  end
end

RSpec.configure do |config|
  config.include Hawkular::Metrics::RSpec

  # Sometimes one wants to check if the real api has
  # changed, so turn off VCR and use live connections
  # instead of recorded cassettes
  if ENV['VCR_OFF'] == '1'
    VCR.eject_cassette
    VCR.turn_off!(ignore_cassettes: true)
    WebMock.allow_net_connect!
    puts 'VCR is turned off!'
  end
end
