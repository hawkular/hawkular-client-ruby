require "#{File.dirname(__FILE__)}/../vcr/vcr_setup"
require "#{File.dirname(__FILE__)}/../spec_helper"

include Hawkular::Inventory
include Hawkular::Operations

# WebSocket communication cannot be faked via VCR cassettes
module Hawkular::Operations::RSpec
  HOST = 'localhost:8080'
  describe 'Websocket connection' do
    it 'should be established', :websocket do
      client = OperationsClient.new(host: HOST,
                                    credentials: {
                                      username: 'jdoe',
                                      password: 'password'
                                    })
      ws = client.ws
      expect(ws).not_to be nil
      expect(ws.open?).to be true
    end
  end

  describe 'Operation', :websocket do
    before(:all) do
      VCR.turn_off!(ignore_cassettes: true)
      WebMock.allow_net_connect!
      @creds = { username: 'jdoe', password: 'password' }
      inventory_client = InventoryClient.new(credentials: @creds)
      @tenant_id = inventory_client.get_tenant
      @feed_id = inventory_client.list_feeds[0]
    end

    before(:each) do |ex|
      unless ex.metadata[:skip_open]
        @client = OperationsClient.new(host: HOST, credentials: @creds)
        @ws = @client.ws
      end
    end

    after(:each) do |ex|
      unless ex.metadata[:skip_close]
        @client.close_connection!
        @client = nil
        @ws = nil
      end
    end

    after(:all) do
      if ENV['VCR_OFF'] != '1'
        VCR.turn_on!
        WebMock.disable_net_connect!
      end
    end

    it 'Redeploy should be performed and eventually respond with success' do
      wf_server_resource_id = 'Local~~'
      alerts_war_resource_id = 'Local~%2Fdeployment%3Dhawkular-alerts-actions-email.war'
      path = CanonicalPath.new(tenant_id: @tenant_id,
                               feed_id: @feed_id,
                               resource_ids: [wf_server_resource_id, alerts_war_resource_id])

      redeploy = {
        operationName: 'Redeploy',
        resourcePath: path.to_s,
        authentication: @creds
      }

      actual_data = {}
      @client.invoke_generic_operation(redeploy) do |on|
        on.success do |data|
          actual_data[:data] = data
        end
        on.failure do |error|
          actual_data[:data] = {}
          puts 'error callback was called, reason: ' + error.to_s
        end
      end

      # expectations don't work from callbacks so waiting for the results via blocking helper `wait_for`
      actual_data = wait_for actual_data
      expect(actual_data['status']).to eq('OK')
      expect(actual_data['resourcePath']).to eq(path.to_s)
      expect(actual_data['message']).to start_with('Performed [Redeploy] on')
    end

    it 'Redeploy should not be performed if resource path is wrong' do
      wf_server_resource_id = 'Local~~'
      wrong_war_resource_id = 'Local~%2Fdeployment%3Dnon-existent.war'
      path = CanonicalPath.new(tenant_id: @tenant_id,
                               feed_id: @feed_id,
                               resource_ids: [wf_server_resource_id, wrong_war_resource_id])

      redeploy = {
        operationName: 'Redeploy',
        resourcePath: path.to_s,
        authentication: @creds
      }
      actual_data = {}
      @client.invoke_generic_operation(redeploy) do |on|
        on.success do |_|
          actual_data[:data] = { error: 'the operation should have failed' }
        end
        on.failure do |error|
          actual_data[:data] = { error: error }
        end
      end
      actual_data = wait_for actual_data
      expect(actual_data[:error]).to start_with('Could not perform [Redeploy] on')
    end

    it 'Disable/Undeploy should be performed and eventually respond with success' do
      wf_server_resource_id = 'Local~~'
      alerts_war_resource_id = 'Local~%2Fdeployment%3Dhawkular-alerts-actions-email.war'
      path = CanonicalPath.new(tenant_id: @tenant_id,
                               feed_id: @feed_id,
                               resource_ids: [wf_server_resource_id, alerts_war_resource_id])

      undeploy = {
        operationName: 'Undeploy',
        resourcePath: path.to_s,
        authentication: @creds
      }
      actual_data = {}
      @client.invoke_generic_operation(undeploy) do |on|
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
      expect(actual_data['message']).to start_with('Performed [Undeploy] on')
    end

    it 'should not be possible to perform on closed client', skip_open: true, skip_close: true do
      @client.close_connection! unless @client.nil?

      # open the connection
      operations_client = OperationsClient.new(credentials: @creds)

      redeploy = {
        operationName: 'Redeploy',
        resourcePath: '/t;t1/f;whatever/r;something',
        authentication: @creds
      }

      # close the connection
      operations_client.close_connection!
      expect do
        operations_client.invoke_generic_operation(redeploy)
      end.to raise_error(RuntimeError, /Handshake with server has not been done./)
    end

    xit 'Remove deployment should be performed and eventually respond with success' do
      wf_server_resource_id = 'Local~~'
      alerts_war_resource_id = 'Local~%2Fdeployment%3Dhawkular-alerts-actions-email.war'
      path = CanonicalPath.new(tenant_id: @tenant_id,
                               feed_id: @feed_id,
                               resource_ids: [wf_server_resource_id, alerts_war_resource_id])
      remove_deployment = {
        operationName: 'Remove',
        resourcePath: path.to_s,
        authentication: @creds
      }
      actual_data = {}
      @client.invoke_generic_operation(remove_deployment) do |on|
        on.success do |data|
          actual_data[:data] = data
        end
        on.failure do |error|
          actual_data[:data] = { 'status' => 'ERROR' }
          puts 'error callback was called, reason: ' + error.to_s
        end
      end
      actual_data = wait_for actual_data
      expect(actual_data['status']).to eq('OK')
      expect(actual_data['message']).to start_with('Performed [Remove] on')
    end

    it 'Redeploy can be run multiple times in parallel' do
      wf_server_resource_id = 'Local~~'
      alerts_war_resource_id = 'Local~%2Fdeployment%3Dhawkular-alerts-actions-email.war'
      console_war_resource_id = 'Local~%2Fdeployment%3Dhawkular-console.war'
      path1 = CanonicalPath.new(tenant_id: @tenant_id,
                                feed_id: @feed_id,
                                resource_ids: [wf_server_resource_id, alerts_war_resource_id])
      path2 = CanonicalPath.new(tenant_id: @tenant_id,
                                feed_id: @feed_id,
                                resource_ids: [wf_server_resource_id, console_war_resource_id])

      redeploy1 = {
        operationName: 'Redeploy',
        resourcePath: path1.to_s,
        authentication: @creds
      }

      redeploy2 = {
        operationName: 'Redeploy',
        resourcePath: path2.to_s,
        authentication: @creds
      }

      # run the first operation w/o registering the callback
      @client.invoke_generic_operation(redeploy1)

      actual_data = {}
      # run the 2nd operation with 2 callback blocks (the happy path and the less happy path)
      @client.invoke_generic_operation(redeploy2) do |on|
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
      expect(actual_data['resourcePath']).to eq(path2.to_s)
      expect(actual_data['message']).to start_with('Performed [Redeploy] on')
    end

    # TODO: enable this test once we have the add_datasource operation implemented so that we can add back removed DS
    # the test works, but it can be run only once per new Hawkular server
    xit 'Remove datasource should be performed and eventually respond with success' do
      wf_server_resource_id = 'Local~~'
      datasource_resource_id = 'Local~%2Fsubsystem%3Ddatasources%2Fdata-source%3DExampleDS'
      path = CanonicalPath.new(tenant_id: @tenant_id,
                               feed_id: @feed_id,
                               resource_ids: [wf_server_resource_id, datasource_resource_id])

      operation = {
        resourcePath: path.to_s,
        authentication: @creds
      }

      actual_data = {}
      @client.invoke_specific_operation(operation, 'RemoveDatasource') do |on|
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
      expect(actual_data['message']).to start_with('Performed [Remove] on')
      expect(actual_data['serverRefreshIndicator']).to eq('RELOAD-REQUIRED')
    end

    it 'add deployment should be doable' do
      # TODO: implement + local path
      wf_server_resource_id = 'Local~~'
      war_file = IO.binread('/home/jkremser/sample.war')
      app_name = 'sample.war'
      wf_path = CanonicalPath.new(tenant_id: @tenant_id,
                                  feed_id: @feed_id,
                                  resource_ids: [wf_server_resource_id]).to_s

      actual_data = {}
      @client.add_deployment(resource_path: wf_path,
                             destination_file_name: app_name,
                             file_binary_content: war_file) do |on|
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
      expect(actual_data['message']).to start_with('Performed [Deploy] on')
      expect(actual_data['destinationFileName']).to eq(app_name)
      expect(actual_data['resourcePath']).to eq(wf_path)
    end

    xit 'add datasource should be doable' do
      # TODO: implement
    end
  end
end
