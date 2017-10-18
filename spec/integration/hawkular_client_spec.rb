require_relative '../vcr/vcr_setup'
require_relative '../spec_helper'

require 'securerandom'

include Hawkular::Inventory
include Hawkular::Operations

# examples that tests the main client which delegates all the calls to Hawkular component clients
module Hawkular::Client::RSpec
  HOST = 'http://localhost:8080'

  describe 'HawkularClient' do
    alias_method :helper_host, :host

    let(:cassette_name) do |example|
      description = example.description
      description
    end

    before(:all) do
      @creds = {
        username: 'jdoe',
        password: 'password'
      }
      ::RSpec::Mocks.with_temporary_scope do
        mock_inventory_client '0.26.0.Final'
        mock_metrics_version
        @hawkular_client = Hawkular::Client.new(entrypoint: HOST, credentials: @creds, options: { tenant: 'hawkular' })
        @hawkular_client.inventory
        @hawkular_client.metrics
      end
      @state = {
        hostname: 'localhost.localdomain',
        feed: nil
      }
    end

    it 'Should err on bad credentials' do
      record('HawkularClient', nil, cassette_name) do
        @creds = {
          username: '-XX-X-jdoe-X',
          password: 'password'
        }
        expect do
          Hawkular::Client.new(entrypoint: HOST, credentials: @creds, options: { tenant: 'hawkular' })
            .inventory_root_resources
        end.to raise_error(Hawkular::BaseClient::HawkularException, 'Unauthorized')
      end
    end

    it 'Should fail when calling method with unknown prefix' do
      expect { @hawkular_client.ynventori_root_resources }.to raise_error(Hawkular::ArgumentError)
      expect { @hawkular_client.root_resources }.to raise_error(Hawkular::ArgumentError)
    end

    it 'Should fail when calling unknown method with known client prefix' do
      expect { @hawkular_client.inventory_lyst_feeds }.to raise_error(NoMethodError)
      expect { @hawkular_client.metrics_lyst_feeds }.to raise_error(NoMethodError)
      expect { @hawkular_client.alerts_lyst_feeds }.to raise_error(NoMethodError)
      expect { @hawkular_client.tokens_lyst_feeds }.to raise_error(NoMethodError)
    end

    context 'and URIs as input' do
      it 'Should work with URI' do
        record('HawkularClient', nil, cassette_name) do
          uri = URI.parse HOST
          opts = { tenant: 'hawkular' }
          mock_metrics_version
          the_client = Hawkular::Client.new(entrypoint: uri, credentials: @creds, options: opts)
          expect { the_client.inventory.root_resources }.to_not raise_error
        end
      end

      it 'Should work with URI on metrics client' do
        uri = URI.parse HOST
        opts = { tenant: 'hawkular' }
        record('HawkularClient', nil, cassette_name) do
          mock_metrics_version
          the_client = Hawkular::Metrics::Client.new(uri, @creds, opts)
          expect { the_client.http_get '/status' }.to_not raise_error
        end
      end

      it 'Should work with https URI on metrics client' do
        uri = URI.parse 'https://localhost:8080'
        opts = { tenant: 'hawkular' }
        mock_metrics_version
        the_client = Hawkular::Metrics::Client.new(uri, @creds, opts)
        expect !the_client.nil?
      end
    end

    context 'and Inventory client' do
      before(:all) do
        ::RSpec::Mocks.with_temporary_scope do
          mock_inventory_client '0.26.0.Final'
          @client = Hawkular::Inventory::Client.create(entrypoint: HOST,
                                                       credentials: @creds,
                                                       options: { tenant: 'hawkular' })
        end
      end

      around(:each) do |example|
        record('HawkularClient', nil, cassette_name, example: example)
      end

      it 'Should list the same root resources' do
        rr1 = @client.root_resources
        rr2 = @hawkular_client.inventory_root_resources

        expect(rr1).to match_array(rr2)
      end

      it 'Should both list WildFlys' do
        resources1 = @client.resources_for_type('WildFly Server')
        resources2 = @hawkular_client.inventory_resources_for_type('WildFly Server')

        expect(resources1).to match_array(resources2)
      end
    end

    context 'and Metrics client' do
      include Hawkular::Metrics::RSpec

      before(:all) do
        ::RSpec::Mocks.with_temporary_scope do
          mock_metrics_version
          opts = { tenant: 'hawkular' }
          @client = Hawkular::Metrics::Client.new(HOST, @creds, opts)
        end
      end

      it 'Should both work the same way when pushing metric data to non-existing counter' do
        id = SecureRandom.uuid
        record('HawkularClient', { id: id }, 'and_Metrics_client/Should both work the same way when' \
                              ' pushing metric data to non-existing counter') do
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
        record('HawkularClient', { id1: id1, id2: id2 }, 'and_Metrics_client/Should both create and return' \
                  'Availability using Hash parameter') do
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
        record('HawkularClient', { id1: id1, id2: id2 }, 'and_Metrics_client/Should both create and retrieve tags'\
                  'for Availability') do
          @client.avail.create(id: id1, tags: { myTag: id1 })
          metric = @hawkular_client.metrics.avail.get(id1)
          expect(metric.id).to eql(id1)
          @hawkular_client.metrics.avail.create(id: id2, tags: { myTag: id2 })
          metric = @client.avail.get(id2)
          expect(metric.id).to eql(id2)
        end
      end

      it 'Should both return the version' do
        record('HawkularClient', nil, 'and_Metrics_client/Should both return the version') do
          data1 = @client.fetch_version_and_status
          data2 = @hawkular_client.metrics.fetch_version_and_status
          expect(data1).to eql(data2)
        end
      end
    end

    context 'and Operations client' do
      include Hawkular::Operations::RSpec

      WebSocketVCR.configure do |c|
        c.hook_uris = ['localhost:8080']
      end

      let(:host) do
        helper_host(:NonSecure)
      end

      let(:options) do
        {
          host: host,
          wait_time: WebSocketVCR.live? ? 1.5 : 2,
          use_secure_connection: false,
          credentials: credentials,
          options: {
            tenant: 'hawkular'
          }
        }
      end

      before(:each) do
        record('HawkularClient/Helpers', nil, 'get_tenant') do
          mock_inventory_client
          @inventory_client = ::Hawkular::Inventory::Client.create(
            options.merge entrypoint: host_with_scheme(host, false))
          inventory_client = @inventory_client
          remove_instance_variable(:@inventory_client)
          @tenant_id = 'hawkular'
          record('HawkularClient/Helpers', { tenant_id: @tenant_id }, 'agent_properties') do
            agent = installed_agent(inventory_client)
            @agent_immutable = agent_immutable?(agent)
          end
        end
      end

      around(:each) do |example|
        record('HawkularClient', nil, cassette_name, example: example)
      end

      it 'Should both work the same way', :websocket do
        record_websocket('HawkularClient', nil, cassette_name) do
          wf_server = @hawkular_client.inventory.resources(typeId: 'WildFly Server', root: true)[0]
          status_war_resource = @hawkular_client.inventory
                                                .children_resources(wf_server.id)
                                                .select { |r| r.name == 'Deployment [hawkular-status.war]' }[0]

          redeploy = {
            operationName: 'Redeploy',
            resourceId: status_war_resource.id,
            feedId: status_war_resource.feed
          }

          actual_data = {}
          client = Hawkular::Operations::Client.new(entrypoint: HOST, credentials: @creds)
          client.invoke_generic_operation(redeploy) do |on|
            on.success do |data|
              actual_data[:data] = data
            end
            on.failure do |error|
              actual_data[:data] = error
            end
          end

          actual_data = wait_for actual_data
          expect(actual_data['status']).to eq('OK') unless @agent_immutable
          expect(actual_data).to include('not allowed because the agent is immutable') if @agent_immutable

          # now do the same on the main client
          actual_data = {}
          @hawkular_client.operations_invoke_generic_operation(redeploy) do |on|
            on.success do |data|
              actual_data[:data] = data
            end
            on.failure do |error|
              actual_data[:data] = error
            end
          end

          actual_data = wait_for actual_data
          expect(actual_data['status']).to eq('OK') unless @agent_immutable
          expect(actual_data).to include('not allowed because the agent is immutable') if @agent_immutable
        end
      end

      it 'Should work initializing with URI' do
        uri = URI.parse HOST
        opts = { tenant: 'hawkular' }
        record_websocket('HawkularClient', nil, cassette_name) do
          mock_metrics_version
          the_client = Hawkular::Client.new(entrypoint: uri, credentials: @creds, options: opts)
          expect { the_client.operations }.to_not raise_error
        end
      end
    end
  end
end
