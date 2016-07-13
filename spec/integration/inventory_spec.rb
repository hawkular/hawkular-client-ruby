require "#{File.dirname(__FILE__)}/../vcr/vcr_setup"
require "#{File.dirname(__FILE__)}/../spec_helper"
require 'securerandom'

module Hawkular::Inventory::RSpec
  ENTRYPOINT = 'http://localhost:8080/hawkular/inventory'
  DEFAULT_VERSION = '0.17.2.Final'
  VERSION = ENV['INVENTORY_VERSION'] || DEFAULT_VERSION

  include Hawkular::Inventory
  xdescribe 'Inventory/Tenants', vcr: { decode_compressed_response: true, record: :new_episodes } do
    it 'Should Get Tenant For Explicit Credentials' do
      # get the client for given endpoint for given credentials
      creds = { username: 'jdoe', password: 'password' }
      mock_inventory_client(VERSION) unless ENV['VCR_UPDATE'] == '1'
      options = { tenant: 'hawkular' }
      client = Hawkular::Inventory::InventoryClient.create(entrypoint: ENTRYPOINT,
                                                           credentials: creds,
                                                           options: options)
      tenant = client.get_tenant(creds)

      if client.version[0] == 0 && client.version[1] < 17
        expect(tenant).to eq('28026b36-8fe4-4332-84c8-524e173a68bf')
      else
        expect(tenant).to eq('hawkular')
      end
    end

    it 'Should Get Tenant For Implicit Credentials' do
      creds = { username: 'jdoe', password: 'password' }
      mock_inventory_client(VERSION) unless ENV['VCR_UPDATE'] == '1'
      options = { tenant: 'hawkular' }
      client = Hawkular::Inventory::InventoryClient.create(entrypoint: ENTRYPOINT,
                                                           credentials: creds,
                                                           options: options)
      tenant = client.get_tenant

      if client.version[0] == 0 && @client.version[1] < 17
        expect(tenant).to eq('28026b36-8fe4-4332-84c8-524e173a68bf')
      else
        expect(tenant).to eq('hawkular')
      end
    end
  end

  describe 'Inventory Connection' do
    it 'Should err on bad credentials' do
      VCR.use_cassette('Inventory/Connection/Should err on bad credentials') do
        @creds = {
          username: '-XX-X-jdoe-X',
          password: 'password'
        }
        expect do
          Hawkular::Inventory::InventoryClient.create(entrypoint: ENTRYPOINT, credentials: @creds)
        end.to raise_error(Hawkular::BaseClient::HawkularException, 'Unauthorized')
      end
    end
  end

  describe 'Inventory' do
    URL_RESOURCE = 'http://bsd.de'

    before(:all) do
      @creds = {
        username: 'jdoe',
        password: 'password'
      }

      options = { decode_compressed_response: true }
      options[:record] = :all if ENV['VCR_UPDATE'] == '1'
      client_options = { tenant: 'hawkular' }

      if ENV['VCR_UPDATE'] == '1'
        VCR.turn_off!(ignore_cassettes: true)
        WebMock.allow_net_connect!
        @client = Hawkular::Inventory::InventoryClient.create(entrypoint: ENTRYPOINT,
                                                              credentials: @creds,
                                                              options: client_options)
        WebMock.disable_net_connect!
        VCR.turn_on!
      else
        ::RSpec::Mocks.with_temporary_scope do
          mock_inventory_client(VERSION) unless ENV['VCR_UPDATE'] == '1'
          @client = Hawkular::Inventory::InventoryClient.create(entrypoint: ENTRYPOINT,
                                                                credentials: @creds,
                                                                options: client_options)
        end
      end

      x, y, = @client.version
      VCR.use_cassette("Inventory/inventory_#{x}_#{y}/Helpers/get_feeds", options) do
        feeds = @client.list_feeds
        @state = {
          feed_uuid: feeds[0]
        }
      end

      # create 1 URL resource and its metrics
      VCR.use_cassette("Inventory/inventory_#{x}_#{y}/Helpers/create_url", options) do
        rest_client = RestClient::Resource.new('http://localhost:8080/hawkular/api/urls',
                                               user: @creds[:username],
                                               password: @creds[:password],
                                               headers: { 'Hawkular-Tenant': 'hawkular' }
                                              )
        url_json = {
          url: URL_RESOURCE
        }.to_json

        begin
          rest_client.post(url_json, content_type: 'application/json')
        rescue
          puts 'failed to create the url'
          # no big deal, the url is probably already there
        end
      end

      sleep 2 if ENV['VCR_UPDATE'] == '1' || ENV['VCR_OFF'] == '1'
    end

    after(:all) do
      require 'fileutils'
      x, y, = @client.version
      FileUtils.rm_rf "#{VCR.configuration.cassette_library_dir}/Inventory/inventory#{x}_#{y}/tmp"
    end

    let(:cassette_name) do |example|
      description = example.description
      description
    end

    let(:feed_id) do
      @state[:feed_uuid]
    end

    let(:wildfly_type) do
      CanonicalPath.new(feed_id: feed_id, resource_type_id: hawk_escape_id('WildFly Server'))
    end

    around(:each) do |example|
      major, minor, = @client.version
      record("Inventory/inventory_#{major}_#{minor}", @state, cassette_name, example: example)
    end

    it 'Should list feeds' do
      feeds = @client.list_feeds

      expect(feeds.size).to be > 0
    end

    it 'Should list resources for feed' do
      resources = @client.list_resources_for_feed feed_id

      expect(resources.size).to be(2)
    end

    it 'Should list feeds when using SSL without certificate' do
      # change this to the real credentials when updating the VCR
      @state[:super_secret_username] = 'username'
      @state[:super_secret_password] = 'password'
      creds = { username: @state[:super_secret_username],
                password: @state[:super_secret_password] }
      tori_url = 'https://hawkular.torii.gva.redhat.com/hawkular/inventory'
      mock_inventory_client(VERSION)
      client = Hawkular::Inventory::InventoryClient.create(entrypoint: tori_url,
                                                           credentials: creds,
                                                           options: { tenant: 'hawkular',
                                                                      verify_ssl: OpenSSL::SSL::VERIFY_NONE
                                                           })
      feeds = client.list_feeds

      expect(feeds.size).to be(1)
    end

    it 'Should list all the resource types' do
      types = @client.list_resource_types
      # new API returns only the feedless types here, while the old one returned all the types
      expect(types.size).to be > 0
    end

    it 'Should list types with feed' do
      types = @client.list_resource_types(feed_id)

      expect(types.size).to be >= 18
    end

    it 'Should list types with bad feed' do
      type = 'does not exist'
      types = @client.list_resource_types(type)
      expect(type).to eq('does not exist')

      expect(types.size).to be(0)
    end

    it 'Should list WildFlys' do
      resources = @client.list_resources_for_type(wildfly_type.to_s)

      expect(resources.size).to be(1)
    end

    it 'Should list WildFlys with props' do
      resources = @client.list_resources_for_type(wildfly_type.to_s, fetch_properties: true)

      expect(resources.size).to be(1)
      wf = resources.first
      expect(wf.properties['Hostname']).not_to be_empty
    end

    it 'Should List datasources with no props' do
      type_path = CanonicalPath.new(feed_id: feed_id, resource_type_id: hawk_escape_id('Datasource'))
      resources = @client.list_resources_for_type(type_path.to_s, fetch_properties: true)

      expect(resources.size).to be > 0
    end

    it 'Should list URLs' do
      type_path = CanonicalPath.new(resource_type_id: hawk_escape_id('URL'))
      resources = @client.list_resources_for_type(type_path.to_s)

      expect(resources.size).to be(1)
      resource = resources[0]
      expect(resource.instance_of? Hawkular::Inventory::Resource).to be_truthy
      # depends how pinger is fast
      expect(2..6).to cover(resource.properties.size)
      expect(resource.properties['url']).to eq(URL_RESOURCE)
    end

    it 'Should list metrics for WildFlys' do
      resources = @client.list_resources_for_type(wildfly_type.to_s)
      wild_fly = resources[0]

      metrics = @client.list_metrics_for_resource(wild_fly.path)

      expect(metrics.size).to be(14)
    end

    it 'Should list children of WildFly' do
      resources = @client.list_resources_for_type(wildfly_type.to_s)
      wild_fly = resources[0]

      children = @client.list_child_resources(wild_fly.path)

      expect(children.size).to be > 10
    end

    it 'Should list children of nested resource' do
      wildfly_res_id = hawk_escape_id 'Local~~'
      datasource_res_id = hawk_escape_id 'Local~/subsystem=datasources/data-source=ExampleDS'
      resource_path = CanonicalPath.new(feed_id: feed_id, resource_ids: [wildfly_res_id, datasource_res_id])
      datasource = @client.get_resource(resource_path.to_s)

      # this was changed
      if @client.version[0] == 0 && @client.version[1] < 17
        expect(datasource.name).to eq('ExampleDS')
      else
        expect(datasource.name).to eq('Datasource [ExampleDS]')
      end

      children = @client.list_child_resources(datasource.path)

      expect(children.size).to be(0)
    end

    it 'Should list recursive children of WildFly' do
      resources = @client.list_resources_for_type(wildfly_type.to_s)
      wild_fly = resources[0]

      children = @client.list_child_resources(wild_fly.path, recursive: true)

      expect(children.size).to be > 40
    end

    it 'Should list relationships of WildFly' do
      resources = @client.list_resources_for_type(wildfly_type.to_s)
      wild_fly = resources[0]

      rels = @client.list_relationships(wild_fly.path)

      expect(rels.size).to be > 40
    end

    it 'Should list heap metrics for WildFlys' do
      resources = @client.list_resources_for_type(wildfly_type.to_s)
      wild_fly = resources[0]

      metrics = @client.list_metrics_for_resource(wild_fly.path, type: 'GAUGE', match: 'Metrics~Heap')
      expect(metrics.size).to be(3)

      metrics = @client.list_metrics_for_resource(wild_fly.path, match: 'Metrics~Heap')
      expect(metrics.size).to be(3)

      metrics = @client.list_metrics_for_resource(wild_fly.path, type: 'GAUGE')
      expect(metrics.size).to be(8)
    end

    it 'Should list metrics of given metric type' do
      type_path = CanonicalPath.new(feed_id: feed_id, metric_type_id: hawk_escape_id('Total Space'))
      metrics = @client.list_metrics_for_metric_type(type_path)

      expect(metrics.size).to be >= 4
    end

    it 'Should list metrics of given resource type' do
      metrics = @client.list_metrics_for_resource_type(wildfly_type.to_s)

      expect(metrics.size).to be(14)
    end

    it 'Should return config data of given resource' do
      resource_path = CanonicalPath.new(feed_id: feed_id, resource_ids: [hawk_escape_id('Local~~')])
      config = @client.get_config_data_for_resource(resource_path)

      # product name is missing
      expect(config['value']['Server State']).to eq('running')
      if @client.version[0] == 0 && @client.version[1] < 17
        expect(config['value']['Product Name']).to eq('Hawkular')
      end
    end

    it 'Should return config data of given nested resource' do
      wildfly_res_id = hawk_escape_id 'Local~~'
      datasource_res_id = hawk_escape_id 'Local~/subsystem=datasources/data-source=ExampleDS'
      resource_path = CanonicalPath.new(feed_id: feed_id, resource_ids: [wildfly_res_id, datasource_res_id])

      config = @client.get_config_data_for_resource(resource_path)

      expect(config['value']['Username']).to eq('sa')
      expect(config['value']['Driver Name']).to eq('h2')
    end

    it 'Should list operation definitions of given resource type' do
      operation_definitions = @client.list_operation_definitions(wildfly_type.to_s)

      expect(operation_definitions).not_to be_empty
      expect(operation_definitions).to include('JDR')
      expect(operation_definitions).to include('Reload')
      expect(operation_definitions).to include('Shutdown')
      expect(operation_definitions).to include('Deploy')
    end

    it 'Should list operation definitions of given resource' do
      resources = @client.list_resources_for_type(wildfly_type.to_s)
      wild_fly = resources[0]
      operation_definitions = @client.list_operation_definitions_for_resource(wild_fly.path.to_s)

      expect(operation_definitions).not_to be_empty
      expect(operation_definitions).to include('JDR')
    end

    it 'Should create a feed' do
      new_feed_id = 'feed_1123sdncisud6237ui23hjbdscuzsad'
      ret = @client.create_feed new_feed_id
      expect(ret).to_not be_nil
      expect(ret['id']).to eq(new_feed_id)
    end

    it 'Should create and delete feed' do
      new_feed_id = 'feed_1123sdn'
      ret = @client.create_feed new_feed_id
      expect(ret).to_not be_nil
      expect(ret['id']).to eq(new_feed_id)

      @client.delete_feed new_feed_id

      feed_list = @client.list_feeds
      expect(feed_list).not_to include(new_feed_id)
    end

    it 'Should create a feed again' do
      new_feed_id = 'feed_1123sdncisud6237ui2378789vvgX'
      @client.create_feed new_feed_id
      @client.create_feed new_feed_id
    end

    it 'Should create a resourcetype' do
      new_feed_id = 'feed_may_exist'
      @client.create_feed new_feed_id

      ret = @client.create_resource_type new_feed_id, 'rt-123', 'ResourceType'
      expect(ret.id).to eq('rt-123')
      expect(ret.name).to eq('ResourceType')
      expect(ret.path).to include('/rt;rt-123')
      expect(ret.path).to include('/f;feed_may_exist')
    end

    it 'Should create a resource' do
      new_feed_id = 'feed_may_exist'
      @client.create_feed new_feed_id
      ret = @client.create_resource_type new_feed_id, 'rt-123', 'ResourceType'
      type_path = ret.path

      @client.create_resource type_path, 'r123', 'My Resource', 'version' => 1.0

      resource_path = CanonicalPath.new(feed_id: new_feed_id, resource_ids: ['r123'])

      r = @client.get_resource(resource_path, false)
      expect(r.id).to eq('r123')
      expect(r.properties).not_to be_empty
    end

    it 'Should create a resource with metric' do
      new_feed_id = 'feed_may_exist'
      @client.create_feed new_feed_id
      ret = @client.create_resource_type new_feed_id, 'rt-123', 'ResourceType'
      type_path = ret.path

      @client.create_resource type_path, 'r124', 'My Resource', 'version' => 1.0
      resource_path = CanonicalPath.new(feed_id: new_feed_id, resource_ids: ['r124'])

      r = @client.get_resource(resource_path, false)
      expect(r.id).to eq('r124')
      expect(r.properties).not_to be_empty

      mt = @client.create_metric_type new_feed_id, 'mt-124'
      expect(mt).not_to be_nil
      expect(mt.id).to eq('mt-124')

      m = @client.create_metric_for_resource mt.path, r.path, 'm-124'
      expect(m).not_to be_nil
      expect(m.id).to eq('m-124')
      expect(m.name).to eq('m-124')

      m = @client.create_metric_for_resource mt.path, r.path, 'm-124-1', 'Metric1'
      expect(m).not_to be_nil
      expect(m.id).to eq('m-124-1')
      expect(m.name).to eq('Metric1')
    end

    it 'Should create a nested resource and metric on it' do
      new_feed_id = 'feed_may_exist'
      @client.create_feed new_feed_id
      ret = @client.create_resource_type new_feed_id, 'rt-123-1', 'ResourceType'
      type_path = ret.path

      parent = @client.create_resource type_path, 'r124-a', 'Res-a'
      nested_resource = @client.create_resource_under_resource type_path, parent.path, 'r124-b', 'Res-a'
      expect(nested_resource.path).to include('r;r124-a/r;r124-b')

      mt = @client.create_metric_type new_feed_id, 'mt-124-a'
      expect(mt).not_to be_nil
      expect(mt.id).to eq('mt-124-a')

      m_name = 'MetricUnderNestedResource'
      m = @client.create_metric_for_resource mt.path, nested_resource.path, 'm-124-a', m_name
      expect(m.id).to eq('m-124-a')
      expect(m.name).to eq(m_name)

      metrics = @client.list_metrics_for_resource nested_resource.path
      expect(metrics.size).to eq(1)
      expect(metrics[0].id).to eq(m.id)
    end

    it 'Should create and get a resource' do
      new_feed_id = 'feed_may_exist'
      @client.create_feed new_feed_id
      ret = @client.create_resource_type new_feed_id, 'rt-123', 'ResourceType'
      type_path = ret.path

      r1 = @client.create_resource type_path, 'r125', 'My Resource', 'version' => 1.0

      r2 = @client.get_resource(r1.path, true)
      expect(r2.id).to eq('r125')
      expect(r1.id).to eq(r2.id)
      expect(r2.properties).not_to be_empty
    end

    it 'Should not find an unknown resource' do
      new_feed_id = 'feed_may_exist'
      path = CanonicalPath.new(feed_id: new_feed_id, resource_ids: [hawk_escape_id('*bla does not exist*')])
      expect { @client.get_resource(path) }
        .to raise_error(Hawkular::BaseClient::HawkularException, /No Resource found/)
    end

    it 'Should reject unknown metric type' do
      new_feed_id = 'feed_may_exist'

      expect { @client.create_metric_type new_feed_id, 'abc', 'FOOBaR' }.to raise_error(RuntimeError,
                                                                                        /Unknown type FOOBAR/)
    end

    let(:example) do |e|
      e
    end

    it 'Client should listen on various inventory events', :websocket do
      WebSocketVCR.configure do |c|
        c.hook_uris = ['localhost:8080']
      end
      uuid_prefix = SecureRandom.uuid
      vcr_options = {
        decode_compressed_response: true,
        erb: {
          uuid_prefix: uuid_prefix
        },
        reverse_substitution: true
      }
      vcr_options[:record] = :all if ENV['VCR_UPDATE'] == '1'
      x, y, = @client.version
      cassette_name = "Inventory/inventory_#{x}_#{y}/Templates/Client_should_listen_on_various_inventory_events"
      WebSocketVCR.use_cassette(cassette_name, vcr_options) do
        id_1 = uuid_prefix + '-r126'
        id_2 = uuid_prefix + '-r127'
        id_3 = uuid_prefix + '-r128'

        new_resource_events = {}
        resources_closable = @client.events do |resource|
          new_resource_events[resource.id] = resource
        end

        deleted_feed_events = {}
        feed_deleted_closable = @client.events('feed', 'deleted') do |feed|
          deleted_feed_events[feed.id] = feed
        end

        new_resource_types_events = {}
        # another breaking change in the new inventory api
        interest = @client.version[0] == 0 && @client.version[1] < 17 ? 'resourcetype' : 'resourceType'
        resource_type_closable = @client.events(interest) do |resource_type|
          new_resource_types_events[resource_type.id] = resource_type
        end

        registered_feed_events = {}
        feeds_closable = @client.events('feed', 'created') do |feed|
          registered_feed_events[feed.id] = feed
        end

        new_feed_id = uuid_prefix + '-feed'
        resource_type_id = uuid_prefix + '-rt-123'
        resource_type_name = 'ResourceType'

        record("Inventory/inventory_#{x}_#{y}",
               { uuid_prefix: uuid_prefix },
               'Helpers/generate_some_events_for_websocket') do
          @client.create_feed new_feed_id
          ret = @client.create_resource_type new_feed_id, resource_type_id, resource_type_name
          type_path = ret.path

          # create 3 resources
          @client.create_resource type_path, id_1, 'My Resource 1', 'version' => 1.0
          @client.create_resource type_path, id_2, 'My Resource 2', 'version' => 1.1
          resources_closable.close
          @client.create_resource type_path, id_3, 'My Resource 3', 'version' => 1.2

          @client.delete_feed new_feed_id
        end

        # wait for the data
        sleep 2 if !WebSocketVCR.cassette || WebSocketVCR.cassette.recording?
        [feed_deleted_closable, resource_type_closable, feeds_closable].each(&:close)
        expect(new_resource_events[id_1]).not_to be_nil
        expect(new_resource_events[id_1].properties['version']).to eq(1.0)
        expect(new_resource_events[id_2]).not_to be_nil
        expect(new_resource_events[id_2].properties['version']).to eq(1.1)
        # resource with id_3 should not be among events, because we stopped listening before creating the 3rd one
        expect(new_resource_events[id_3]).to be_nil

        expect(registered_feed_events[new_feed_id]).not_to be_nil
        expect(registered_feed_events[new_feed_id].id).to eq(new_feed_id)

        expect(deleted_feed_events[new_feed_id]).not_to be_nil
        expect(deleted_feed_events[new_feed_id].id).to eq(new_feed_id)

        expect(new_resource_types_events[resource_type_id]).not_to be_nil
        expect(new_resource_types_events[resource_type_id].id).to eq(resource_type_id)
        expect(new_resource_types_events[resource_type_id].name).to eq(resource_type_name)
      end
    end

    # TODO: enable when inventory supports it
    # it 'Should return the version' do
    #   data = @client.get_version_and_status
    #   expect(data).not_to be_nil
    # end
  end
end
