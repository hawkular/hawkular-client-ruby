require_relative '../vcr/vcr_setup'
require_relative '../spec_helper'

require 'securerandom'

include Hawkular::Inventory
include Hawkular::Operations

# examples that tests the main client which delegates all the calls to Hawkular component clients
module Hawkular::Client::RSpec
  HOST = 'http://localhost:8080'.freeze

  describe 'HawkularClient' do
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
        mock_inventory_client '0.9.8.Final'
        mock_metrics_version
        @hawkular_client = Hawkular::Client.new(entrypoint: HOST, credentials: @creds, options: { tenant: 'hawkular' })
        @hawkular_client.inventory
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
      expect { @hawkular_client.ynventori_root_resources }.to raise_error(NoMethodError)
      expect { @hawkular_client.root_resources }.to raise_error(NoMethodError)
    end

    it 'Should fail when calling unknown method with known client prefix' do
      expect { @hawkular_client.inventory_lyst_feeds }.to raise_error(NoMethodError)
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

    context 'and Operations client' do
      include Hawkular::Operations::RSpec

      WebSocketVCR.configure do |c|
        c.hook_uris = ['localhost:8080']
      end

      let(:options) do
        {
          entrypoint: HOST,
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
          @inventory_client = ::Hawkular::Inventory::Client.create(options)
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
          wf_server = @hawkular_client.inventory.resources(typeId: 'WildFly Server WF10', root: true)[0]
          restart = {
            resource_id: wf_server.id,
            feed_id: wf_server.feed,
            deployment_name: 'hawkular-status.war',
            sender_request_id: '**fixed-req-id**'
          }

          actual_data = {}
          client = Hawkular::Operations::Client.new(entrypoint: HOST, credentials: @creds)
          client.restart_deployment(restart) do |on|
            on.success do |data|
              actual_data[:data] = data
            end
            on.failure do |error|
              actual_data[:data] = error
            end
          end

          actual_data = wait_for actual_data
          expect(actual_data['status']).to eq('OK')

          # now do the same on the main client
          actual_data = {}
          restart[:sender_request_id] = '**another-fixed-req-id**'
          @hawkular_client.operations_restart_deployment(restart) do |on|
            on.success do |data|
              actual_data[:data] = data
            end
            on.failure do |error|
              actual_data[:data] = error
            end
          end

          actual_data = wait_for actual_data
          expect(actual_data['status']).to eq('OK')
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
