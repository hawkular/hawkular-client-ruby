require "#{File.dirname(__FILE__)}/../vcr/vcr_setup"
require "#{File.dirname(__FILE__)}/../spec_helper"
require 'securerandom'

# examples that tests the uber client which delegates all the calls to Hawkular component clients
module Hawkular::UberClient::RSpec
  describe 'UberClient' do
    before(:all) do
      @creds = {
        username: 'jdoe',
        password: 'password'
      }
      @uber_client = Hawkular::UberClient.new(credentials: @creds)
      @state = {
        hostname: 'localhost.localdomain',
        feed: nil
      }
    end

    it 'Should fail when calling method with unknown prefix' do
      expect { @uber_client.ynventori_list_feeds }.to raise_error(RuntimeError)
      expect { @uber_client.list_feeds }.to raise_error(RuntimeError)
    end

    it 'Should fail when calling unknown method with known client prefix' do
      expect { @uber_client.inventory_lyst_feeds }.to raise_error(NoMethodError)
    end

    context 'and Inventory client', vcr: { decode_compressed_response: true } do
      before(:all) do
        @client = Hawkular::Inventory::InventoryClient.create(credentials: @creds)
      end

      it 'Should list the same feeds' do
        feeds1 = @client.list_feeds
        feeds2 = @uber_client.inventory_list_feeds

        expect(feeds1).to match_array(feeds2)
        @state[:feed] = feeds1[0] unless feeds1[0].nil?
      end

      it 'Should list the same resource types' do
        types1 = @client.list_resource_types
        types2 = @uber_client.inventory_list_resource_types

        expect(types1).to match_array(types2)
      end

      it 'Should list same types when param is given' do
        types1 = @client.list_resource_types(@state[:feed])
        types2 = @uber_client.inventory_list_resource_types(@state[:feed])

        expect(types1).to match_array(types2)
      end

      it 'Should both list types with bad feed' do
        type = 'does not exist'
        types1 = @client.list_resource_types(type)
        types2 = @uber_client.inventory_list_resource_types(type)

        expect(types1).to match_array(types2)
      end

      it 'Should both list WildFlys' do
        resources1 = @client.list_resources_for_type(@state[:feed], 'WildFly Server')
        resources2 = @uber_client.inventory_list_resources_for_type(@state[:feed], 'WildFly Server')

        expect(resources1).to match_array(resources2)
      end

      it 'Should both create and delete feed' do
        feed_id1 = 'feed_1123sdn'
        feed_id2 = 'feed_1124sdn'
        @client.create_feed feed_id1
        @uber_client.inventory_create_feed feed_id2

        feed_list = @client.list_feeds
        expect(feed_list).to include(feed_id1)
        expect(feed_list).to include(feed_id2)

        @client.delete_feed feed_id2
        @uber_client.inventory.delete_feed feed_id1

        feed_list = @uber_client.inventory_list_feeds
        expect(feed_list).not_to include(feed_id1)
        expect(feed_list).not_to include(feed_id2)
      end
    end

    context 'and Metrics client' do
      include Hawkular::Metrics::RSpec

      before(:all) do
        @client = Hawkular::Metrics::Client.new('http://localhost:8080/hawkular/metrics', @creds)
      end

      it 'Should both work the same way when pushing metric data to non-existing counter' do
        id = SecureRandom.uuid

        VCR.use_cassette('UberClient/and_Metrics_client/Should both work the same way when' \
                             ' pushing metric data to non-existing counter',
                         erb: { id: id }, record: :none, decode_compressed_response: true
                        ) do
          @client.counters.push_data(id, value: 4)

          data = @uber_client.metrics.counters.get_data(id)
          expect(data.size).to be 1
          counter = @uber_client.metrics.counters.get(id)
          expect(counter.id).to eql(id)
        end
      end

      it 'Should both create and return Availability using Hash parameter' do
        id1 = SecureRandom.uuid
        id2 = SecureRandom.uuid
        VCR.use_cassette(
          'UberClient/and_Metrics_client/Should both create and return Availability using Hash parameter',
          erb: { id1: id1, id2: id2 }, record: :none, decode_compressed_response: true
        ) do
          @client.avail.create(id: id1, dataRetention: 123, tags: { some: 'value' })
          metric = @uber_client.metrics.avail.get(id1)
          expect(metric.id).to eql(id1)
          expect(metric.data_retention).to eql(123)

          @uber_client.metrics.avail.create(id: id2, dataRetention: 321, tags: { some: 'value' })
          metric = @client.avail.get(id2)
          expect(metric.id).to eql(id2)
          expect(metric.data_retention).to eql(321)
        end
      end

      it 'Should both update tags for Availability' do
        id1 = SecureRandom.uuid
        id2 = SecureRandom.uuid

        VCR.use_cassette('UberClient/and_Metrics_client/Should both create and retrieve tags for Availability',
                         erb: { id1: id1, id2: id2 }, record: :none, decode_compressed_response: true
                        ) do
          @client.avail.create(id: id1, tags: { myTag: id1 })
          metric = @uber_client.metrics.avail.get(id1)
          expect(metric.id).to eql(id1)

          @uber_client.metrics.avail.create(id: id2, tags: { myTag: id2 })
          metric = @client.avail.get(id2)
          expect(metric.id).to eql(id2)
        end
      end

      it 'Should both return the version' do
        VCR.use_cassette('UberClient/and_Metrics_client/Should both return the version') do
          data1 = @client.fetch_version_and_status
          data2 = @uber_client.metrics.fetch_version_and_status
          expect(data1).to eql(data2)
        end
      end
    end

    context 'and Operations client' do
      include Hawkular::Operations::RSpec

      it 'Should both work the same way', :websocket do
        VCR.turn_off!(ignore_cassettes: true)
        WebMock.allow_net_connect!
        tenant_id = @uber_client.inventory_get_tenant
        tenant_id2 = @uber_client.inventory.get_tenant
        expect(tenant_id).to eql(tenant_id2)

        feed_id = @uber_client.inventory.list_feeds.first
        wf_server_resource_id = 'Local~~'
        alerts_war_resource_id = 'Local~%2Fdeployment%3Dhawkular-alerts-actions-email.war'
        path = Hawkular::Inventory::CanonicalPath.new(tenant_id: tenant_id,
                                                      feed_id: feed_id,
                                                      resource_ids: [wf_server_resource_id, alerts_war_resource_id])

        redeploy = {
          operationName: 'Redeploy',
          resourcePath: path.to_s
        }

        actual_data = {}
        client = Hawkular::Operations::OperationsClient.new(credentials: @creds)
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

        # now do the same on the uber client
        actual_data = {}
        @uber_client.operations_invoke_generic_operation(redeploy) do |on|
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

        if ENV['VCR_OFF'] != '1'
          VCR.turn_on!
          WebMock.disable_net_connect!
        end
      end
    end
  end
end
