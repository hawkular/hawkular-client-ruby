# This needs to go before all requires to be able to record full coverage
require 'coveralls'
Coveralls.wear!

# Now the application requires.
require 'hawkular/hawkular_client'
require 'hawkular/client_utils'
require 'rspec/core'
require 'rspec/mocks'
require 'socket'
require 'uri'
require 'yaml'
require 'json'

module Hawkular::Inventory::RSpec
  def setup_inventory_client(entrypoint, options = {})
    credentials = {
      username: options[:username].nil? ? config['user'] : options[:username],
      password: options[:password].nil? ? config['password'] : options[:password]
    }
    @client = Hawkular::Inventory::Client.new(entrypoint, credentials, options)
  end

  def mock_inventory_client(for_version = '0.16.1.Final')
    allow_any_instance_of(Hawkular::Inventory::Client).to receive(:fetch_version_and_status).and_return(
      'Implementation-Version' => for_version
    )
  end
end

module Hawkular::InventoryV4::RSpec
  def setup_inventory_client(entrypoint, options = {})
    credentials = {
      username: options[:username].nil? ? config['user'] : options[:username],
      password: options[:password].nil? ? config['password'] : options[:password]
    }
    @client = Hawkular::InventoryV4::Client.new(entrypoint, credentials, options)
  end

  def mock_inventory_client(for_version = '0.16.1.Final')
    allow_any_instance_of(Hawkular::Inventory::Client).to receive(:fetch_version_and_status).and_return(
      'Implementation-Version' => for_version
    )
  end
end

module Hawkular::Metrics::RSpec
  def setup_client_without_tenant(options = {})
    options = options.dup
    options[:tenant] = nil
    mocked_version = options[:mocked_version]
    ::RSpec::Mocks.with_temporary_scope do
      mock_metrics_version(mocked_version) unless mocked_version.nil?
      @client = Hawkular::Metrics::Client.new(entrypoint(options[:type], 'metrics'),
                                              credentials(options), options)
      return @client
    end
  end

  def setup_client(options = {})
    options = options.dup
    options[:tenant] ||= 'hawkular'
    mocked_version = options[:mocked_version]
    ::RSpec::Mocks.with_temporary_scope do
      mock_metrics_version(mocked_version) unless mocked_version.nil?
      @client = Hawkular::Metrics::Client.new(entrypoint(options[:type], 'metrics'),
                                              credentials(options), options)
    end
    @client
  end

  def setup_v8_client(options = {})
    options = options.dup
    options[:tenant] ||= 'hawkular'
    options[:verify_ssl] ||= OpenSSL::SSL::VERIFY_NONE
    ::RSpec::Mocks.with_temporary_scope do
      mock_metrics_version '0.8.0'
      @client = Hawkular::Metrics::Client.new(entrypoint('v8', 'metrics'),
                                              credentials_v8(options), options)
    end
    @client
  end

  def credentials_v8(options = {})
    {
      token: options[:token].nil? ? config['token_v8'] : options[:token]
    }
  end

  def credentials(options = {})
    {
      username: options[:username].nil? ? config['user'] : options[:username],
      password: options[:password].nil? ? config['password'] : options[:password]
    }
  end

  def mock_metrics_version(version = '0.9.0.Final')
    allow_any_instance_of(Hawkular::Metrics::Client).to receive(:fetch_version_and_status).and_return(
      'Implementation-Version' => version
    )
  end

  # more or less generic method common for all metric types (counters, gauges, availabilities)
  def create_metric_using_hash(endpoint, id, tenant_id)
    endpoint.create(id: id, dataRetention: 123, tags: { some: 'value' })
    metric = endpoint.get(id)

    expect(metric).to be_a(Hawkular::Metrics::MetricDefinition)
    expect(metric.id).to eql(id)
    expect(metric.data_retention).to eql(123)
    expect(metric.tenant_id).to eql(tenant_id)
  end

  def create_metric_using_md(endpoint, id, tags = nil)
    metric = Hawkular::Metrics::MetricDefinition.new
    metric.id = id
    metric.data_retention = 90
    metric.tags = tags.nil? ? { tag: 'value' } : tags
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
  SLEEP_SECONDS = 0.1
  MAX_ATTEMPTS = 200

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

  def wait_while
    fast = WebSocketVCR.cassette && !WebSocketVCR.cassette.recording?
    sleep_interval = SLEEP_SECONDS * (fast ? 1 : 10)
    sleep_interval *= 3 if ENV['TRAVIS']
    attempt = 0
    sleep sleep_interval while yield && (attempt += 1) < MAX_ATTEMPTS
    if attempt == MAX_ATTEMPTS
      puts 'timeout hit'
    else
      return
    end
  end

  def hash_include_all(hash, keys)
    keys.all? do |key|
      hash.key? key
    end
  end

  def host_with_scheme(host, use_secure_connection)
    "#{use_secure_connection ? 'https' : 'http'}://#{host}"
  end
end

# globally used helper functions
module Helpers
  def config
    @config ||= YAML.load(
      File.read(File.expand_path('endpoint.yml', __dir__))
    )
  end

  def entrypoint(type, component = nil)
    base = config[type.to_s.downcase]
    entrypoint = "#{base['is_secure'] ? 'https' : 'http'}://#{base['host']}:#{base['port']}/"
    entrypoint << config[component] unless component.nil?
  end

  def host(type)
    base = config[type.to_s.downcase]
    "#{base['host']}:#{base['port']}"
  end

  def installed_agent(inventory, feed_id)
    resource_type_path = inventory.feed_cp(feed_id).resource_type('Hawkular WildFly Agent')
    inventory.list_resources_for_type(resource_type_path, true).first
  end

  def agent_in_container?(agent)
    agent.properties['In Container'] == 'true'
  end

  def agent_immutable?(agent)
    agent.properties['Immutable'] == 'true'
  end

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
      text.gsub! v.to_s, "<%= #{k} %>"
    end

    File.open(output_file_path, 'w') { |file| file.write text }
    File.delete(input_file_path)
  end

  def record(prefix, bindings, explicit_cassette_name, example: nil)
    run = lambda do
      unless example.nil?
        if example.respond_to?(:run)
          example.run
        elsif example.respond_to?(:call)
          example.call
        end
      end
      yield if block_given?
    end
    record_cassette(prefix, bindings, explicit_cassette_name, run)
  end

  def record_cleanup(prefix)
    FileUtils.rm_rf "#{VCR.configuration.cassette_library_dir}/#{prefix}/tmp"
  end

  def record_websocket(prefix, bindings, explicit_cassette_name, example = nil)
    prefix.gsub!(/\s/, '_')
    explicit_cassette_name.gsub!(/\s/, '_')
    run = lambda do
      unless example.nil?
        if example.respond_to?(:run)
          example.run
        elsif example.respond_to?(:call)
          example.call
        end
      end
      yield if block_given?
    end

    record_websocket_cassette(prefix, bindings, explicit_cassette_name, run)
  end

  private

  def record_cassette(prefix, bindings, explicit_cassette_name, run_lambda)
    if ENV['VCR_UPDATE'] == '1' && bindings
      VCR.use_cassette(prefix + '/tmp/' + explicit_cassette_name,
                       decode_compressed_response: true,
                       record: :all) do
        run_lambda.call
      end
      make_template prefix, explicit_cassette_name, bindings
    else
      VCR.use_cassette(prefix + '/Templates/' + explicit_cassette_name,
                       decode_compressed_response: true,
                       erb: bindings,
                       record: ENV['VCR_UPDATE'] == '1' ? :all : :none) do
        run_lambda.call
      end
    end
  end

  def record_websocket_cassette(prefix, bindings, explicit_cassette_name, run_lambda)
    options = {
      record: :none,
      decode_compressed_response: true
    }
    options[:erb] = bindings if bindings
    if ENV['VCR_UPDATE'] == '1'
      options[:record] = :all
      options[:reverse_substitution] = true if bindings
    end
    WebSocketVCR.use_cassette(prefix + '/' + explicit_cassette_name, options) do
      run_lambda.call
    end
  end
end

RSpec.configure do |config|
  config.include Helpers
  config.include Hawkular::Inventory::RSpec
  config.include Hawkular::Metrics::RSpec
  config.include Hawkular::Operations::RSpec
  config.include Hawkular::ClientUtils
  config.include Hawkular::Inventory

  # skip the tests that have the :skip metadata on them
  config.filter_run_excluding :skip

  # Sometimes one wants to check if the real api has
  # changed, so turn off VCR and use live connections
  # instead of recorded cassettes
  if ENV['VCR_OFF'] == '1'
    VCR.eject_cassette
    VCR.turn_off!(ignore_cassettes: true)
    WebSocketVCR.turn_off! # TODO: this does not work as the impl is empty
    WebMock.allow_net_connect!
    puts 'VCR is turned off!'
  end

  module RestClient
    class Request
      def default_headers
        {
          accept: '*/*',
          accept_encoding: 'identity',
          user_agent: 'hawkular-client-ruby'
        }
      end
    end
  end
end
