# This needs to go before all requires to be able to record full coverage
require 'coveralls'
Coveralls.wear!
# Now the application requires.
require 'hawkular/hawkular_client'
require 'rspec/core'
require 'rspec/mocks'
require 'socket'
require 'uri'
require 'yaml'
require 'json'

module Hawkular::Metrics::RSpec
  def setup_client(options = {})
    credentials = {
      username: options[:username].nil? ? config['user'] : options[:username],
      password: options[:password].nil? ? config['password'] : options[:password]
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
  SLEEP_SECONDS = 0.04
  MAX_ATTEMPTS = 60

  def wait_for(object)
    fast = WebSocketVCR.cassette && !WebSocketVCR.cassette.recording?
    sleep_interval = SLEEP_SECONDS * (fast ? 1 : 10)
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

# globally used helper functions
module Helpers
  def make_template(base_directory, cassette_name, bindings)
    cassette = cassette_name.gsub(/\s+/, '_')
    input_file_path = "#{VCR.configuration.cassette_library_dir}/#{base_directory}/tmp/#{cassette}.yml"
    return unless File.exist? input_file_path
    output_file_path = "#{VCR.configuration.cassette_library_dir}/#{base_directory}/Templates/#{cassette}.yml"

    dirname = File.dirname(output_file_path)
    # make sure the directory structure is there
    FileUtils.mkdir_p(dirname) unless File.directory?(dirname)

    text = File.read(input_file_path)
    bindings.select { |_, v| v.size >= 3 }.each do |k, v|
      text.gsub! v, "<%= #{k} %>"
    end

    File.open(output_file_path, 'w') { |file| file.write text }
    File.delete(input_file_path)
  end

  def record(prefix, bindings, explicit_cassette_name, example: nil)
    run = lambda do
      example.run unless example.nil?
      yield if block_given?
    end

    if (!example.nil? && example.metadata[:update_template]) || ENV['VCR_UPDATE'] == '1'
      VCR.use_cassette(prefix + '/tmp/' + explicit_cassette_name,
                       decode_compressed_response: true,
                       record: :all) do
        run.call
      end
      make_template prefix, explicit_cassette_name, bindings
    else
      VCR.use_cassette(prefix + '/Templates/' + explicit_cassette_name,
                       decode_compressed_response: true,
                       erb: bindings,
                       record: :none) do
        run.call
      end
    end
  end
end

RSpec.configure do |config|
  config.include Helpers
  config.include Hawkular::Metrics::RSpec
  config.include Hawkular::Operations::RSpec

  # skip the tests that have the :skip metadata on them
  config.filter_run_excluding :skip

  # Sometimes one wants to check if the real api has
  # changed, so turn off VCR and use live connections
  # instead of recorded cassettes
  if ENV['VCR_OFF'] == '1'
    VCR.eject_cassette
    VCR.turn_off!(ignore_cassettes: true)
    WebSocketVCR.turn_off!
    WebMock.allow_net_connect!
    puts 'VCR is turned off!'
  end
end
