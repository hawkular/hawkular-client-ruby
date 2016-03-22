# This needs to go before all requires to be able to record full coverage
require 'coveralls'
Coveralls.wear!
# Now the application requires.
require 'hawkular/hawkular_all'
require 'rspec/core'
require 'rspec/mocks'
require 'socket'
require 'uri'
require 'yaml'

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

  # more or less generic method common for all metric types (counters, gauges, availabilities)
  def create_metric_using_hash(endpoint, id, tenant_id)
    endpoint.create(id: id, dataRetention: 123, tags: { some: 'value' }, tenantId: tenant_id)
    metric = endpoint.get(id)

    expect(metric).to be_a(Hawkular::Metrics::MetricDefinition)
    expect(metric.id).to eql(id)
    expect(metric.data_retention).to eql(123)
    expect(metric.tenant_id).to eql(tenant_id)
  end

  def create_metric_using_md(endpoint, id)
    metric = Hawkular::Metrics::MetricDefinition.new
    metric.id = id
    metric.data_retention = 90
    metric.tags = { tag: 'value' }
    endpoint.create(metric)

    created = endpoint.get(metric.id)
    expect(created).to be_a(Hawkular::Metrics::MetricDefinition)
    expect(created.id).to eql(metric.id)
    expect(created.data_retention).to eql(metric.data_retention)
  end

  def push_data_to_non_existing_metric(endpoint, data, id)
    # push one value without timestamp (which means now)
    endpoint.push_data(id, data)

    data = endpoint.get_data(id)
    expect(data.size).to be 1

    # verify metric was auto-created
    counter = endpoint.get(id)
    expect(counter).to be_a(Hawkular::Metrics::MetricDefinition)
    expect(counter.id).to eql(id)
  end

  def update_metric_by_tags(endpoint, id)
    endpoint.create(id: id, tags: { myTag: id })
    metric = endpoint.get(id)
    metric.tags = { newTag: 'newValue' }
    endpoint.update_tags(metric)

    metric = endpoint.get(id)
    expect(metric.tags).to include('newTag' => 'newValue', 'myTag' => id)

    # query API for a metric with given tag
    data = endpoint.query(myTag: id)
    expect(data.size).to be 1
  end
end

module Hawkular::Operations::RSpec
  SLEEP_SECONDS = 0.05
  MAX_ATTEMPTS = 50

  def wait_for(object)
    sleep_interval = SLEEP_SECONDS * (ENV['VCR_OFF'] == '1' ? 1 : 10)
    attempt = 0
    sleep sleep_interval while object[:data].nil? && (attempt += 1) < MAX_ATTEMPTS
    if attempt == MAX_ATTEMPTS
      puts 'timeout hit'
      {}
    else
      object[:data]
    end
  end
end

RSpec.configure do |config|
  config.include Hawkular::Metrics::RSpec
  config.include Hawkular::Operations::RSpec

  # skip the tests that require websocket communication (cannot be recorded by VCR)
  if ENV['WEBSOCKET_ON'].nil? || ENV['WEBSOCKET_ON'] != '1'
    config.filter_run_excluding :websocket
  end

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
