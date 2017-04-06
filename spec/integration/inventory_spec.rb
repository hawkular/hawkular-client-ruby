require_relative '../vcr/vcr_setup'
require_relative '../spec_helper'

require 'securerandom'

module Hawkular::Inventory::RSpec
  DEFAULT_VERSION = '0.17.2.Final'
  VERSION = ENV['INVENTORY_VERSION'] || DEFAULT_VERSION

  SKIP_SECURE_CONTEXT = ENV['SKIP_SECURE_CONTEXT'] || '1'

  URL_RESOURCE = 'http://bsd.de'

  NON_SECURE_CONTEXT = :NonSecure
  SECURE_CONTEXT = :Secure

  [NON_SECURE_CONTEXT, SECURE_CONTEXT].each do |security_context|
    next if security_context == SECURE_CONTEXT && SKIP_SECURE_CONTEXT == '1'

    context "#{security_context}" do
      include Hawkular::Inventory

      alias_method :helper_entrypoint, :entrypoint

      let(:entrypoint) do
        helper_entrypoint(security_context, 'inventory')
      end

      describe 'Inventory Tenants' do
        let(:cassette_name) do |example|
          description = example.description
          description
        end

        around(:each) do |example|
          record("Inventory/#{security_context}/Tenants", credentials, cassette_name, example: example)
        end

        it 'Should Get Tenant For Explicit Credentials' do
          # get the client for given endpoint for given credentials
          creds = credentials
          mock_inventory_client(VERSION) unless ENV['VCR_UPDATE'] == '1' || ENV['VCR_OFF'] == '1'
          options = { tenant: 'hawkular' }
          client = setup_inventory_client entrypoint, options
          tenant = client.get_tenant(creds)
          expect(tenant).to eq('hawkular')
        end

        it 'Should Get Tenant For Implicit Credentials' do
          creds = credentials
          mock_inventory_client(VERSION) unless ENV['VCR_UPDATE'] == '1' || ENV['VCR_OFF'] == '1'
          options = { tenant: 'hawkular' }
          client = setup_inventory_client entrypoint, options
          tenant = client.get_tenant(creds)
          expect(tenant).to eq('hawkular')
        end
      end

      describe 'Inventory Connection' do
        let(:cassette_name) do |example|
          description = example.description
          description
        end

        around(:each) do |example|
          record("Inventory/#{security_context}/Connection", credentials, cassette_name, example: example)
        end

        it 'Should err on bad credentials' do
          @creds = credentials
          @creds[:username] << @creds[:password]
          VCR.eject_cassette
          record("Inventory/#{security_context}/Connection", @creds, cassette_name) do
            expect do
              Hawkular::Inventory::Client.create(entrypoint: entrypoint, credentials: @creds)
            end.to raise_error(Hawkular::BaseClient::HawkularException, 'Unauthorized')
          end
        end
      end

      describe 'Inventory' do
        created_feeds = Set.new

        before(:all) do
          @creds = credentials

          @state = {
            super_secret_username: @creds[:username],
            super_secret_password: @creds[:password]
          }

          client_options = { tenant: 'hawkular' }

          if ENV['VCR_UPDATE'] == '1'
            VCR.turn_off!(ignore_cassettes: true)
            WebMock.allow_net_connect!
            @client = setup_inventory_client helper_entrypoint(security_context, 'inventory'), client_options
            WebMock.disable_net_connect!
            VCR.turn_on!
          else
            ::RSpec::Mocks.with_temporary_scope do
              mock_inventory_client(VERSION) unless ENV['VCR_UPDATE'] == '1'
              @client = setup_inventory_client helper_entrypoint(security_context, 'inventory'), client_options
            end
          end

          x, y, = @client.version
          record("Inventory/#{security_context}/inventory_#{x}_#{y}", @state.clone, 'Helpers/get_feeds') do
            feeds = @client.list_feeds
            @state[:feed_uuid] = feeds[0]
          end

          record("Inventory/#{security_context}/inventory_#{x}_#{y}", @state.clone, 'Helpers/wait_for_wildfly') do
            wait_while do
              @client.list_resources_for_feed(@state[:feed_uuid]).length < 2
            end
          end if ENV['RUN_ON_LIVE_SERVER'] == '1'

          # create 1 URL resource and its metrics
          record("Inventory/#{security_context}/inventory_#{x}_#{y}", @state.clone, 'Helpers/create_url') do
            headers = {}
            headers[:'Hawkular-Tenant'] = client_options[:tenant]
            rest_client = RestClient::Resource.new(helper_entrypoint(security_context, 'urls'),
                                                   user: credentials[:username],
                                                   password: credentials[:password],
                                                   headers: headers)
            url_json = {
              url: URL_RESOURCE
            }.to_json

            begin
              rest_client.post(url_json, content_type: 'application/json')
            rescue
              puts 'failed to create the url, it might be already there'
              # no big deal, the url is probably already there
            end
          end

          sleep 2 if ENV['VCR_UPDATE'] == '1' || ENV['VCR_OFF'] == '1'
        end

        before(:each) do
          inventory_create_feed_method = @client.method(:create_feed)
          allow(@client).to receive(:create_feed) do |feed|
            created_feeds << feed
            inventory_create_feed_method.call(feed)
          end
        end

        after(:all) do
          require 'fileutils'
          x, y, = @client.version
          FileUtils.rm_rf "#{VCR.configuration.cassette_library_dir}"\
          "/Inventory/#{security_context}/inventory#{x}_#{y}/tmp"

          if ENV['VCR_UPDATE'] == '1' || ENV['VCR_OFF'] == '1'
            VCR.turn_off!(ignore_cassettes: true)
            WebMock.allow_net_connect!
            created_feeds.each do |feed|
              begin
                @client.delete_feed feed
                # rubocop:disable HandleExceptions
              rescue
                # rubocop:enable HandleExceptions
              end
            end
            WebMock.disable_net_connect!
            VCR.turn_on!
          end
        end

        let(:cassette_name) do |example|
          description = example.description
          description
        end

        let(:feed_id) do
          @state[:feed_uuid]
        end

        let(:wildfly_type) do
          Hawkular::Inventory::CanonicalPath.new(feed_id: feed_id, resource_type_id: hawk_escape_id('WildFly Server'))
        end

        around(:each) do |example|
          major, minor, = @client.version
          record("Inventory/#{security_context}/inventory_#{major}_#{minor}", @state, cassette_name, example: example)
        end

        it 'Should list feeds' do
          feeds = @client.list_feeds

          expect(feeds.size).to be > 0
        end

        it 'Should list resources for feed' do
          resources = @client.list_resources_for_feed feed_id

          expect(resources.size).to be(2)
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
          type_path = Hawkular::Inventory::CanonicalPath.new(
            feed_id: feed_id,
            resource_type_id: hawk_escape_id('Datasource'))
          resources = @client.list_resources_for_type(type_path.to_s, fetch_properties: true)

          expect(resources.size).to be > 0
        end

        it 'Should list URLs' do
          type_path = Hawkular::Inventory::CanonicalPath.new(resource_type_id: hawk_escape_id('URL'))
          resources = @client.list_resources_for_type(type_path.to_s)
          expect(resources.size).to be > 0
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
          resource_path = Hawkular::Inventory::CanonicalPath.new(
            feed_id: feed_id,
            resource_ids: [wildfly_res_id, datasource_res_id])
          datasource = @client.get_resource(resource_path.to_s)

          expect(datasource.name).to eq('Datasource [ExampleDS]')
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
          expect(rels[0].to_h['source']).not_to be_empty
        end

        it 'Should list heap metrics for WildFlys' do
          resources = @client.list_resources_for_type(wildfly_type.to_s)
          wild_fly = resources[0]

          metrics = @client.list_metrics_for_resource(wild_fly.path, type: 'gauge', match: 'Metrics~Heap')
          expect(metrics.size).to be(3)

          metrics = @client.list_metrics_for_resource(wild_fly.path, match: 'Metrics~Heap')
          expect(metrics.size).to be(3)

          metrics = @client.list_metrics_for_resource(wild_fly.path, type: 'gauge')
          expect(metrics.size).to be(8)
        end

        it 'Should list metrics of given metric type' do
          type_path = Hawkular::Inventory::CanonicalPath.new(
            feed_id: feed_id,
            metric_type_id: hawk_escape_id('Platform_File Store_Total Space'))
          metrics = @client.list_metrics_for_metric_type(type_path)

          expect(metrics.size).to be >= 2
        end

        it 'Should list metrics of given resource type' do
          metrics = @client.list_metrics_for_resource_type(wildfly_type.to_s)

          expect(metrics.size).to be(14)
        end

        it 'Should have the same requested metric type id' do
          metric_type_id = 'Server Availability~Server Availability'
          type_path = Hawkular::Inventory::CanonicalPath.new(
            feed_id: feed_id,
            metric_type_id: hawk_escape_id(metric_type_id))
          metrics = @client.list_metrics_for_metric_type(type_path)

          expect(metrics.size).to be > 0
          expect(metrics).to all(have_attributes(type_id: metric_type_id))
        end

        it 'Should return config data of given resource' do
          resource_path = Hawkular::Inventory::CanonicalPath.new(
            feed_id: feed_id,
            resource_ids: [hawk_escape_id('Local~~')])
          config = @client.get_config_data_for_resource(resource_path)

          expect(config['value']['Server State']).to eq('running')
          # expect(config['value']['Product Name']).to eq('Hawkular')
        end

        it 'Should return config data of given nested resource' do
          wildfly_res_id = hawk_escape_id 'Local~~'
          datasource_res_id = hawk_escape_id 'Local~/subsystem=datasources/data-source=ExampleDS'
          resource_path = Hawkular::Inventory::CanonicalPath.new(
            feed_id: feed_id,
            resource_ids: [wildfly_res_id, datasource_res_id])

          config = @client.get_config_data_for_resource(resource_path)

          expect(config['value']['Username']).to eq('sa')
          expect(config['value']['Driver Name']).to eq('h2')
        end

        it 'Should get resource with its configurations' do
          wildfly_res_id = hawk_escape_id 'Local~~'
          datasource_res_id = hawk_escape_id 'Local~/subsystem=datasources/data-source=ExampleDS'
          resource_path = Hawkular::Inventory::CanonicalPath.new(
            feed_id: feed_id,
            resource_ids: [wildfly_res_id, datasource_res_id])

          resource = @client.get_resource resource_path, true

          expect(resource.properties['Username']).to eq('sa')
          expect(resource.properties['Driver Name']).to eq('h2')
        end

        it 'Should list operation definitions of given resource type' do
          operation_definitions = @client.list_operation_definitions(wildfly_type.to_s)

          expect(operation_definitions).not_to be_empty
          expect(operation_definitions).to include('JDR')
          expect(operation_definitions).to include('Reload')
          expect(operation_definitions).to include('Shutdown')
          expect(operation_definitions).to include('Deploy')
          shutdown_def = operation_definitions.fetch 'Shutdown'
          expect(shutdown_def.params).to include('timeout')
          expect(shutdown_def.params).to include('restart')
          restart_param = shutdown_def.params.fetch 'restart'
          expect(restart_param['type']).to eq('bool')
          resume_def = operation_definitions.fetch 'Resume'
          expect(resume_def.params).to be {}
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

          resource_path = Hawkular::Inventory::CanonicalPath.new(feed_id: new_feed_id, resource_ids: ['r123'])

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
          resource_path = Hawkular::Inventory::CanonicalPath.new(feed_id: new_feed_id, resource_ids: ['r124'])

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
          new_feed_id = "#{security_context}_feed_may_exist"
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
          new_feed_id = "#{security_context}_feed_may_exist"
          @client.create_feed new_feed_id
          ret = @client.create_resource_type new_feed_id, 'rt-123', 'ResourceType'
          type_path = ret.path

          r1 = @client.create_resource type_path, 'r125', 'My Resource', 'version' => 1.0

          r2 = @client.get_resource(r1.path, true)
          expect(r2.id).to eq('r125')
          expect(r1.id).to eq(r2.id)
          expect(r2.properties).not_to be_empty
        end

        it 'Should have a consistent behaviour when creating an already existing resource' do
          new_feed_id = "#{security_context}_feed_may_exist"
          @client.create_feed new_feed_id
          ret = @client.create_resource_type new_feed_id, 'rt-123', 'ResourceType'
          type_path = ret.path

          r1 = @client.create_resource type_path, 'r999', 'My Resource', 'version' => 1.0
          r2 = @client.create_resource type_path, 'r999', 'My Resource', 'version' => 1.0

          r3 = @client.create_resource_under_resource type_path, r1.path, 'r1000', 'My Resource', 'version' => 1.0
          r4 = @client.create_resource_under_resource type_path, r1.path, 'r1000', 'My Resource', 'version' => 1.0

          expect(r1).to eq(r2)
          expect(r3).to eq(r4)
        end

        it 'Should return data from get_entity' do
          new_feed_id = 'feed_may_exist'
          @client.create_feed new_feed_id
          ret = @client.create_resource_type new_feed_id, 'dummy-resource-type', 'ResourceType'
          type_path = ret.path
          entity = @client.get_entity(type_path)

          expect(entity['path']).to eq(type_path)
          expect(entity['name']).to eq('ResourceType')
          expect(entity['id']).to eq('dummy-resource-type')
        end

        it 'Should not find an unknown resource' do
          new_feed_id = 'feed_may_exist'
          path = Hawkular::Inventory::CanonicalPath.new(
            feed_id: new_feed_id,
            resource_ids: [hawk_escape_id('*bla does not exist*')])
          expect { @client.get_resource(path) }
            .to raise_error(Hawkular::BaseClient::HawkularException, /No Resource found/)
        end

        it 'Should reject unknown metric type' do
          new_feed_id = 'feed_may_exist'

          expect { @client.create_metric_type new_feed_id, 'abc', 'FOOBaR' }.to raise_error(RuntimeError,
                                                                                            /Unknown type foobar/)
        end

        let(:example) do |e|
          e
        end

        it 'Client should listen on various inventory events' do
          WebSocketVCR.configure do |c|
            c.hook_uris = [host(security_context)]
          end
          uuid_prefix = SecureRandom.uuid
          x, y, = @client.version
          record_websocket("Inventory/#{security_context}/inventory_#{x}_#{y}",
                           { uuid_prefix: uuid_prefix },
                           'Client_should_listen_on_various_inventory_events') do
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
            interest = 'resourceType'
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

            record("Inventory/#{security_context}/inventory_#{x}_#{y}",
                   { uuid_prefix: uuid_prefix }.merge(credentials),
                   'Helpers/generate_some_events_for_websocket') do
              @client.create_feed new_feed_id
              ret = @client.create_resource_type new_feed_id, resource_type_id, resource_type_name
              type_path = ret.path

              # create 3 resources
              @client.create_resource type_path, id_1, 'My Resource 1', 'version' => 1.0
              @client.create_resource type_path, id_2, 'My Resource 2', 'version' => 1.1
              # Wait for id_1 and id_2 before stop listening.
              wait_while do
                !hash_include_all(new_resource_events, [id_1, id_2])
              end
              resources_closable.close
              @client.create_resource type_path, id_3, 'My Resource 3', 'version' => 1.2

              @client.delete_feed new_feed_id
            end

            # wait for the data
            wait_while do
              [
                !hash_include_all(new_resource_events, [id_1, id_2]),
                !registered_feed_events.key?(new_feed_id),
                !deleted_feed_events.key?(new_feed_id),
                !new_resource_types_events.key?(resource_type_id)
              ].any?
            end
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

        it 'Should return the version' do
          data = @client.fetch_version_and_status
          expect(data).not_to be_nil
        end
      end
    end
  end

  describe 'Inventory' do
    it 'Should list feeds when using SSL without certificate, disabling the verify' do
      tori_url = 'https://hawkular.torii.gva.redhat.com/hawkular/inventory'
      record 'Inventory', credentials, 'Should list feeds when using SSL without certificate' do
        client = setup_inventory_client tori_url, tenant: 'hawkular', verify_ssl: OpenSSL::SSL::VERIFY_NONE
        feeds = client.list_feeds
        expect(feeds.size).to be(1)
      end
    end
  end unless ENV['SKIP_SSL_WITHOUT_CERTIFICATE_TEST'] == '1'
end
