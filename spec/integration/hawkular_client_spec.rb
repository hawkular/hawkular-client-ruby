require "#{File.dirname(__FILE__)}/../vcr/vcr_setup"
require "#{File.dirname(__FILE__)}/../spec_helper"
require 'securerandom'

# examples that tests the main client which delegates all the calls to Hawkular component clients
module Hawkular::Client::RSpec
  HOST = 'http://localhost:8080'

  describe 'HawkularClient' do
    before(:all) do
      @creds = {
        username: 'jdoe',
        password: 'password'
      }
      ::RSpec::Mocks.with_temporary_scope do
        mock_inventory_client
        @hawkular_client = Hawkular::Client.new(entrypoint: HOST, credentials: @creds, options: { tenant: 'hawkular' })
      end
      @state = {
        hostname: 'localhost.localdomain',
        feed: nil
      }
    end

    it 'Should err on bad credentials' do
      VCR.use_cassette('HawkularClient/Should err on bad credentials') do
        @creds = {
          username: '-XX-X-jdoe-X',
          password: 'password'
        }
        expect do
          Hawkular::Client.new(entrypoint: HOST, credentials: @creds)
        end.to raise_error(Hawkular::BaseClient::HawkularException, 'Unauthorized')
      end
    end

    it 'Should fail when calling method with unknown prefix' do
      expect { @hawkular_client.ynventori_list_feeds }.to raise_error(RuntimeError)
      expect { @hawkular_client.list_feeds }.to raise_error(RuntimeError)
    end

    it 'Should fail when calling unknown method with known client prefix' do
      expect { @hawkular_client.inventory_lyst_feeds }.to raise_error(NoMethodError)
    end

    context 'and URIs as input', vcr: { decode_compressed_response: true } do
      it 'Should work with URI' do
        uri = URI.parse HOST
        opts = { tenant: 'hawkular' }

        the_client = Hawkular::Client.new(entrypoint: uri, credentials: @creds, options: opts)
        expect { the_client.inventory.list_feeds }.to_not raise_error
      end

      it 'Should work with URI on metrics client' do
        uri = URI.parse HOST
        opts = { tenant: 'hawkular' }

        the_client = Hawkular::Metrics::Client.new(uri, @creds, opts)
        expect { the_client.http_get '/status' }.to_not raise_error
      end

      it 'Should work with https URI on metrics client' do
        uri = URI.parse 'https://localhost:8080'
        opts = { tenant: 'hawkular' }

        the_client = Hawkular::Metrics::Client.new(uri, @creds, opts)
        expect !the_client.nil?
      end
    end

    context 'and Inventory client', vcr: { decode_compressed_response: true } do
      before(:all) do
        ::RSpec::Mocks.with_temporary_scope do
          mock_inventory_client
          @client = Hawkular::Inventory::InventoryClient.create(entrypoint: HOST,
                                                                credentials: @creds,
                                                                options: { tenant: 'hawkular' })
        end
      end

      it 'Should list the same feeds' do
        feeds1 = @client.list_feeds
        feeds2 = @hawkular_client.inventory_list_feeds

        expect(feeds1).to match_array(feeds2)
        @state[:feed] = feeds1[0] unless feeds1[0].nil?
      end

      it 'Should list the same resource types' do
        types1 = @client.list_resource_types
        types2 = @hawkular_client.inventory_list_resource_types

        expect(types1).to match_array(types2)
      end

      it 'Should list same types when param is given' do
        types1 = @client.list_resource_types(@state[:feed])
        types2 = @hawkular_client.inventory_list_resource_types(@state[:feed])

        expect(types1).to match_array(types2)
      end

      it 'Should both list types with bad feed' do
        type = 'does not exist'
        types1 = @client.list_resource_types(type)
        types2 = @hawkular_client.inventory_list_resource_types(type)

        expect(types1).to match_array(types2)
      end

      it 'Should both list WildFlys' do
        path = Hawkular::Inventory::CanonicalPath.new(feed_id: @state[:feed],
                                                      resource_type_id: hawk_escape_id('WildFly Server'))
        resources1 = @client.list_resources_for_type(path.to_s)
        resources2 = @hawkular_client.inventory_list_resources_for_type(path)

        expect(resources1).to match_array(resources2)
      end

      it 'Should both create and delete feed' do
        feed_id1 = 'feed_1123sdn'
        feed_id2 = 'feed_1124sdn'
        @client.create_feed feed_id1
        @hawkular_client.inventory_create_feed feed_id2

        feed_list = @client.list_feeds
        expect(feed_list).to include(feed_id1)
        expect(feed_list).to include(feed_id2)

        @client.delete_feed feed_id2
        @hawkular_client.inventory.delete_feed feed_id1

        feed_list = @hawkular_client.inventory_list_feeds
        expect(feed_list).not_to include(feed_id1)
        expect(feed_list).not_to include(feed_id2)
      end
    end

    context 'and Metrics client' do
      include Hawkular::Metrics::RSpec

      before(:all) do
        @client = Hawkular::Metrics::Client.new(HOST, @creds)
      end

      it 'Should both work the same way when pushing metric data to non-existing counter' do
        id = SecureRandom.uuid

        VCR.use_cassette('HawkularClient/and_Metrics_client/Should both work the same way when' \
                             ' pushing metric data to non-existing counter',
                         erb: { id: id }, record: :none, decode_compressed_response: true
                        ) do
          @client.counters.push_data(id, value: 4)

          data = @hawkular_client.metrics.counters.get_data(id)
          expect(data.size).to be 1
          counter = @hawkular_client.metrics.counters.get(id)
          expect(counter.id).to eql(id)
        end
      end

      it 'Should both create and return Availability using Hash parameter' do
        id1 = SecureRandom.uuid
        id2 = SecureRandom.uuid
        VCR.use_cassette(
          'HawkularClient/and_Metrics_client/Should both create and return Availability using Hash parameter',
          erb: { id1: id1, id2: id2 }, record: :none, decode_compressed_response: true
        ) do
          @client.avail.create(id: id1, dataRetention: 123, tags: { some: 'value' })
          metric = @hawkular_client.metrics.avail.get(id1)
          expect(metric.id).to eql(id1)
          expect(metric.data_retention).to eql(123)

          @hawkular_client.metrics.avail.create(id: id2, dataRetention: 321, tags: { some: 'value' })
          metric = @client.avail.get(id2)
          expect(metric.id).to eql(id2)
          expect(metric.data_retention).to eql(321)
        end
      end

      it 'Should both update tags for Availability' do
        id1 = SecureRandom.uuid
        id2 = SecureRandom.uuid

        VCR.use_cassette('HawkularClient/and_Metrics_client/Should both create and retrieve tags for Availability',
                         erb: { id1: id1, id2: id2 }, record: :none, decode_compressed_response: true
                        ) do
          @client.avail.create(id: id1, tags: { myTag: id1 })
          metric = @hawkular_client.metrics.avail.get(id1)
          expect(metric.id).to eql(id1)

          @hawkular_client.metrics.avail.create(id: id2, tags: { myTag: id2 })
          metric = @client.avail.get(id2)
          expect(metric.id).to eql(id2)
        end
      end

      it 'Should both return the version' do
        VCR.use_cassette('HawkularClient/and_Metrics_client/Should both return the version') do
          data1 = @client.fetch_version_and_status
          data2 = @hawkular_client.metrics.fetch_version_and_status
          expect(data1).to eql(data2)
        end
      end
    end

    context 'and Operations client', vcr: { decode_compressed_response: true } do
      include Hawkular::Operations::RSpec

      WebSocketVCR.configure do |c|
        c.hook_uris = ['localhost:8080']
      end

      let(:example) do |e|
        e
      end

      it 'Should both work the same way', :websocket do
        tenant_id = @hawkular_client.inventory_get_tenant
        tenant_id2 = @hawkular_client.inventory.get_tenant
        expect(tenant_id).to eql(tenant_id2)

        feed_id = @hawkular_client.inventory.list_feeds.first
        wf_server_resource_id = 'Local~~'
        alerts_war_resource_id = 'Local~%2Fdeployment%3Dhawkular-alerts-actions-email.war'

        WebSocketVCR.record(example, self) do
          path = Hawkular::Inventory::CanonicalPath.new(tenant_id: tenant_id,
                                                        feed_id: feed_id,
                                                        resource_ids: [wf_server_resource_id, alerts_war_resource_id])

          redeploy = {
            operationName: 'Redeploy',
            resourcePath: path.to_s
          }

          actual_data = {}
          client = Hawkular::Operations::OperationsClient.new(entrypoint: HOST, credentials: @creds)
          client.invoke_generic_operation(redeploy) do |on|
            on.success do |data|
              actual_data[:data] = data
            end
            on.failure do |error|
              actual_data[:data] = {}
              puts 'error callback was called, reason: ' + error.to_s
            end
          end

          actual_data = wait_for actual_data
          expect(actual_data['status']).to eq('OK')

          # now do the same on the main client
          actual_data = {}
          @hawkular_client.operations_invoke_generic_operation(redeploy) do |on|
            on.success do |data|
              actual_data[:data] = data
            end
            on.failure do |error|
              actual_data[:data] = {}
              puts 'error callback was called, reason: ' + error.to_s
            end
          end

          actual_data = wait_for actual_data
          expect(actual_data['status']).to eq('OK')
        end
      end

      it 'Should work initializing with URI' do
        uri = URI.parse HOST
        opts = { tenant: 'hawkular' }
        WebSocketVCR.record(example, self) do
          the_client = Hawkular::Client.new(entrypoint: uri, credentials: @creds, options: opts)
          expect { the_client.operations }.to_not raise_error
        end
      end

      xit 'Should both reuse the websocket connection', :websocket do
        WebSocketVCR.record(example, self) do
        end
      end
    end
  end
end
