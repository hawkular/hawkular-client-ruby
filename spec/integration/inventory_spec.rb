require "#{File.dirname(__FILE__)}/../vcr/vcr_setup"
require "#{File.dirname(__FILE__)}/../spec_helper"
require 'securerandom'

module Hawkular::Inventory::RSpec
  describe 'Inventory/Tenants', vcr: { decode_compressed_response: true } do
    it 'Should Get Tenant For Explicit Credentials' do
      # get the client for given endpoint for given credentials
      creds = { username: 'jdoe', password: 'password' }
      client = Hawkular::Inventory::InventoryClient.create(entrypoint: 'http://localhost:8080/hawkular/inventory',
                                                           credentials: creds)

      tenant = client.get_tenant(creds)

      expect(tenant).to eq('28026b36-8fe4-4332-84c8-524e173a68bf')
    end

    it 'Should Get Tenant For Implicit Credentials' do
      creds = { username: 'jdoe', password: 'password' }
      client = Hawkular::Inventory::InventoryClient.create(credentials: creds)

      tenant = client.get_tenant

      expect(tenant).to eq('28026b36-8fe4-4332-84c8-524e173a68bf')
    end
  end

  describe 'Inventory' do
    before(:all) do
      @creds = {
        username: 'jdoe',
        password: 'password'
      }
      @client = Hawkular::Inventory::InventoryClient.create(credentials: @creds)
      options = { decode_compressed_response: true }
      options[:record] = :all if ENV['VCR_UPDATE'] == '1'
      VCR.use_cassette('Inventory/Helpers/get_feeds', options) do
        feeds = @client.list_feeds
        @state = {
          feed_uuid: feeds[0]
        }
      end
    end

    after(:all) do
      require 'fileutils'
      FileUtils.rm_rf "#{VCR.configuration.cassette_library_dir}/Inventory/tmp"
    end

    let(:cassette_name) do |e|
      description = e.description
      description
    end

    let(:feed_id) do
      @state[:feed_uuid]
    end

    around(:each) do |e|
      record('Inventory', @state, cassette_name, example: e)
    end

    it 'Should list feeds' do
      feeds = @client.list_feeds

      expect(feeds.size).to be(1)
    end

    it 'Should list all the resource types' do
      types = @client.list_resource_types
      expect(types.size).to be(19)
    end

    it 'Should list types with feed' do
      types = @client.list_resource_types(feed_id)

      expect(types.size).to be(18)
    end

    it 'Should list types with bad feed' do
      type = 'does not exist'
      types = @client.list_resource_types(type)
      expect(type).to eq('does not exist')

      expect(types.size).to be(0)
    end

    it 'Should list WildFlys' do
      resources = @client.list_resources_for_type(feed_id, 'WildFly Server')

      expect(resources.size).to be(1)
      wf = resources.first
      expect(wf.properties.size).to be(0)
    end

    it 'Should list WildFlys with props' do
      resources = @client.list_resources_for_type(feed_id, 'WildFly Server', true)

      expect(resources.size).to be(1)
      wf = resources.first
      expect(wf.properties['Hostname']).not_to be_empty
    end

    it 'Should List datasources with no props' do
      resources = @client.list_resources_for_type(feed_id, 'Datasource', true)

      expect(resources.size).to be(2)
      wf = resources.first
      expect(wf.properties.size).to be(0) # They have no props
    end

    it 'Should list URLs' do
      resources = @client.list_resources_for_type(nil, 'URL')

      expect(resources.size).to be(1)
      resource = resources[0]
      expect(resource.instance_of? Hawkular::Inventory::Resource).to be_truthy
      expect(resource.properties.size).to be(6)
      expect(resource.properties['url']).to eq('http://bsd.de')
    end

    it 'Should list metrics for WildFlys' do
      resources = @client.list_resources_for_type(feed_id, 'WildFly Server')
      expect(resources.size).to be(1)

      wild_fly = resources[0]

      metrics = @client.list_metrics_for_resource(wild_fly)

      expect(metrics.size).to be(14)
    end

    it 'Should list children of WildFly' do
      resources = @client.list_resources_for_type(feed_id, 'WildFly Server')
      expect(resources.size).to be(1)

      wild_fly = resources[0]

      children = @client.list_child_resources(wild_fly)

      expect(children.size).to be(22)
    end

    it 'Should list recursive children of WildFly' do
      resources = @client.list_resources_for_type(feed_id, 'WildFly Server')
      wild_fly = resources[0]

      children = @client.list_child_resources(wild_fly, recursive: true)

      expect(children.size).to be(251)
    end

    it 'Should list relationships of WildFly' do
      resources = @client.list_resources_for_type(feed_id, 'WildFly Server')
      wild_fly = resources[0]

      rels = @client.list_relationships(wild_fly)

      expect(rels.size).to be(61)
    end

    it 'Should list heap metrics for WildFlys' do
      resources = @client.list_resources_for_type(feed_id, 'WildFly Server')
      expect(resources.size).to be(1)

      wild_fly = resources[0]

      metrics = @client.list_metrics_for_resource(wild_fly, type: 'GAUGE', match: 'Metrics~Heap')
      expect(metrics.size).to be(3)

      metrics = @client.list_metrics_for_resource(wild_fly, match: 'Metrics~Heap')
      expect(metrics.size).to be(3)

      metrics = @client.list_metrics_for_resource(wild_fly, type: 'GAUGE')
      expect(metrics.size).to be(8)
    end

    it 'Should list metrics of given metric type' do
      metrics = @client.list_metrics_for_metric_type(feed_id, 'Total Space')

      expect(metrics.size).to be(7)
    end

    it 'Should list metrics of given resource type' do
      metrics = @client.list_metrics_for_resource_type(feed_id, 'WildFly Server')

      expect(metrics.size).to be(14)
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

      @client.create_resource new_feed_id, type_path, 'r123', 'My Resource', 'version' => 1.0

      r = @client.get_resource(new_feed_id, 'r123', false)
      expect(r.id).to eq('r123')
      expect(r.properties).not_to be_empty
    end

    it 'Should create a resource with metric' do
      new_feed_id = 'feed_may_exist'
      @client.create_feed new_feed_id
      ret = @client.create_resource_type new_feed_id, 'rt-123', 'ResourceType'
      type_path = ret.path

      @client.create_resource new_feed_id, type_path, 'r124', 'My Resource', 'version' => 1.0

      r = @client.get_resource(new_feed_id, 'r124', false)
      expect(r.id).to eq('r124')
      expect(r.properties).not_to be_empty

      r = @client.create_metric_type new_feed_id, 'mt-124'
      expect(r).not_to be_nil
      expect(r.id).to eq('mt-124')

      m = @client.create_metric_for_resource new_feed_id, 'm-124', r.path, 'r124'
      expect(m).not_to be_nil
      expect(m.id).to eq('m-124')
      expect(m.name).to eq('m-124')

      m = @client.create_metric_for_resource new_feed_id, 'm-124-1', r.path, 'r124', 'Metric1'
      expect(m).not_to be_nil
      expect(m.id).to eq('m-124-1')
      expect(m.name).to eq('Metric1')
    end

    it 'Should create and get a resource' do
      new_feed_id = 'feed_may_exist'
      @client.create_feed new_feed_id
      ret = @client.create_resource_type new_feed_id, 'rt-123', 'ResourceType'
      type_path = ret.path

      @client.create_resource new_feed_id, type_path, 'r125', 'My Resource', 'version' => 1.0

      r = @client.get_resource(new_feed_id, 'r125', true)
      expect(r.id).to eq('r125')
      expect(r.properties).not_to be_empty
    end

    it 'Should not find an unknown resource' do
      new_feed_id = 'feed_may_exist'

      expect { @client.get_resource(new_feed_id, '*bla does not exist*') }
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
      cassette_name = 'Inventory/Templates/Client_should_listen_on_various_inventory_events'
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
        resource_type_closable = @client.events('resourcetype') do |resource_type|
          new_resource_types_events[resource_type.id] = resource_type
        end

        registered_feed_events = {}
        feeds_closable = @client.events('feed', 'created') do |feed|
          registered_feed_events[feed.id] = feed
        end

        new_feed_id = uuid_prefix + '-feed'
        resource_type_id = uuid_prefix + '-rt-123'
        resource_type_name = 'ResourceType'

        record('Inventory',
               { uuid_prefix: uuid_prefix },
               'Helpers/generate_some_events_for_websocket') do
          @client.create_feed new_feed_id
          ret = @client.create_resource_type new_feed_id, resource_type_id, resource_type_name
          type_path = ret.path

          # create 3 resources
          @client.create_resource new_feed_id, type_path, id_1, 'My Resource 1', 'version' => 1.0
          @client.create_resource new_feed_id, type_path, id_2, 'My Resource 2', 'version' => 1.1
          resources_closable.close
          @client.create_resource new_feed_id, type_path, id_3, 'My Resource 3', 'version' => 1.2

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
