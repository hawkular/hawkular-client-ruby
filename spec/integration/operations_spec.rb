require "#{File.dirname(__FILE__)}/../vcr/vcr_setup"
require "#{File.dirname(__FILE__)}/../spec_helper"
require 'securerandom'

include Hawkular::Inventory
include Hawkular::Operations

# examples for operations, it uses the websocket communication
module Hawkular::Operations::RSpec
  HOST = 'localhost:8080'
  describe 'Operation/Websocket connection', vcr: { decode_compressed_response: true } do
    let(:example) do |e|
      e
    end

    it 'should be established' do
      WebSocketVCR.configure do |c|
        c.hook_uris = [HOST]
      end

      WebSocketVCR.record(example, self) do
        client = OperationsClient.new(host: HOST,
                                      wait_time: WebSocketVCR.live? ? 1.5 : 0,
                                      credentials: {
                                        username: 'jdoe',
                                        password: 'password'
                                      })
        ws = client.ws
        expect(ws).not_to be nil
        expect(ws.open?).to be true
      end
    end
  end

  describe 'Operation/Operation', :websocket, vcr: { decode_compressed_response: true } do
    let(:example) do |e|
      e
    end

    before(:all) do
      VCR.use_cassette('Operation/Helpers/get_tenant', decode_compressed_response: true) do
        @creds = { username: 'jdoe', password: 'password' }
        inventory_client = InventoryClient.create(credentials: @creds)
        @tenant_id = inventory_client.get_tenant
        VCR.use_cassette('Operation/Helpers/get_feed', decode_compressed_response: true) do
          @feed_id = inventory_client.list_feeds[0]
        end
        @random_uuid = 'random'
      end
    end

    before(:each) do |ex|
      unless ex.metadata[:skip_open]
        @client = OperationsClient.new(credentials: @creds,
                                       wait_time: WebSocketVCR.live? ? 1.5 : 0)
        @ws = @client.ws
      end
    end

    around(:each) do |ex|
      if ex.metadata[:websocket]
        WebSocketVCR.configure do |c|
          c.hook_uris = [HOST]
        end
        WebSocketVCR.record(ex, self) do
          ex.run
        end
      else
        ex.run
      end
    end

    after(:each) do |ex|
      unless ex.metadata[:skip_close]
        @client.close_connection!
        @client = nil
        @ws = nil
      end
    end

    it 'Add JDBC driver should add the driver' do
      wf_server_resource_id = 'Local~~'
      driver_name = 'CreatedByRubyDriver' + @random_uuid
      driver_bits = IO.binread("#{File.dirname(__FILE__)}/../resources/driver.jar")
      wf_path = CanonicalPath.new(tenant_id: @tenant_id,
                                  feed_id: @feed_id,
                                  resource_ids: [wf_server_resource_id]).to_s

      actual_data = {}
      @client.add_jdbc_driver(resource_path: wf_path,
                              driver_jar_name: 'driver.jar',
                              driver_name: driver_name,
                              module_name: 'foo.bar.' + @random_uuid, # jboss module
                              driver_class: 'com.mysql.jdbc.Driver',
                              binary_content: driver_bits) do |on|
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
      expect(actual_data['message']).to start_with('Added JDBC Driver')
      expect(actual_data['driverName']).to eq(driver_name)
    end

    it 'Redeploy should be performed and eventually respond with success' do
      wf_server_resource_id = 'Local~~'
      alerts_war_resource_id = 'Local~%2Fdeployment%3Dhawkular-alerts-actions-email.war'
      path = CanonicalPath.new(tenant_id: @tenant_id,
                               feed_id: @feed_id,
                               resource_ids: [wf_server_resource_id, alerts_war_resource_id])

      redeploy = {
        operationName: 'Redeploy',
        resourcePath: path.to_s
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
        resourcePath: path.to_s
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

    it 'Undeploy should be performed and eventually respond with success' do
      wf_server_resource_id = 'Local~~'
      alerts_war_resource_id = 'Local~%2Fdeployment%3Dhawkular-alerts-actions-email.war'
      path = CanonicalPath.new(tenant_id: @tenant_id,
                               feed_id: @feed_id,
                               resource_ids: [wf_server_resource_id, alerts_war_resource_id])

      undeploy = {
        operationName: 'Undeploy',
        resourcePath: path.to_s
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

    it 'Add datasource should be doable' do
      wf_server_resource_id = 'Local~~'
      wf_path = CanonicalPath.new(tenant_id: @tenant_id,
                                  feed_id: @feed_id,
                                  resource_ids: [wf_server_resource_id]).to_s
      payload = {
        # compulsory fields
        resourcePath: wf_path,
        xaDatasource: false,
        datasourceName: 'CreatedByRubyDS' + @random_uuid,
        jndiName: 'java:jboss/datasources/CreatedByRubyDS' + @random_uuid,
        driverName: 'h2',
        # this is probably a bug (driver class should be already defined in driver)
        driverClass: 'org.h2.Driver',
        connectionUrl: 'dbc:h2:mem:ruby;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE',

        # optional
        datasourceProperties: {
          someKey: 'someValue'
        },
        userName: 'sa',
        password: 'sa',
        securityDomain: 'other'
        # xaDataSourceClass: 'clazz' for xa DS
      }

      actual_data = {}
      @client.add_datasource(payload) do |on|
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
      expect(actual_data['message']).to start_with('Added Datasource')
      expect(actual_data['xaDatasource']).to be_falsey
      expect(actual_data['datasourceName']).to eq(payload[:datasourceName])
      expect(actual_data['resourcePath']).to eq(payload[:resourcePath])
    end

    it 'should not be possible to perform on closed client', skip_open: true, skip_close: true do
      @client.close_connection! unless @client.nil?

      # open the connection
      operations_client = OperationsClient.new(credentials: @creds)

      redeploy = {
        operationName: 'Redeploy',
        resourcePath: '/t;t1/f;whatever/r;something'
      }

      # close the connection
      operations_client.close_connection!
      expect do
        operations_client.invoke_generic_operation(redeploy)
      end.to raise_error(RuntimeError, /Handshake with server has not been done./)
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
        resourcePath: path1.to_s
      }

      redeploy2 = {
        operationName: 'Redeploy',
        resourcePath: path2.to_s
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

    it 'Add deployment should be doable' do
      wf_server_resource_id = 'Local~~'
      app_name = 'sample.war'
      war_file = IO.binread("#{File.dirname(__FILE__)}/../resources/#{app_name}")
      wf_path = CanonicalPath.new(tenant_id: @tenant_id,
                                  feed_id: @feed_id,
                                  resource_ids: [wf_server_resource_id]).to_s

      actual_data = {}
      @client.add_deployment(resource_path: wf_path,
                             destination_file_name: app_name,
                             binary_content: war_file) do |on|
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

    it 'Remove deployment should be performed and eventually respond with success' do
      wf_server_resource_id = 'Local~~'
      sample_app_resource_id = 'Local~%2Fdeployment=sample.war'
      path = CanonicalPath.new(tenant_id: @tenant_id,
                               feed_id: @feed_id,
                               resource_ids: [wf_server_resource_id, sample_app_resource_id])
      remove_deployment = {
        operationName: 'Remove',
        resourcePath: path.to_s
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

    it 'Remove datasource should be performed and eventually respond with success' do
      wf_server_resource_id = 'Local~~'
      datasource_resource_id = 'Local~%2Fsubsystem%3Ddatasources%2Fdata-source%3DCreatedByRubyDS' + @random_uuid
      path = CanonicalPath.new(tenant_id: @tenant_id,
                               feed_id: @feed_id,
                               resource_ids: [wf_server_resource_id, datasource_resource_id])

      operation = {
        resourcePath: path.to_s
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

    it 'Remove JDBC driver should be performed and eventually respond with success' do
      wf_server_resource_id = 'Local~~'
      driver_resource_id = 'Local~%2Fsubsystem%3Ddatasources%2Fjdbc-driver%3DCreatedByRubyDriver' + @random_uuid
      path = CanonicalPath.new(tenant_id: @tenant_id,
                               feed_id: @feed_id,
                               resource_ids: [wf_server_resource_id, driver_resource_id]).to_s

      actual_data = {}
      @client.invoke_specific_operation({ resourcePath: path }, 'RemoveJdbcDriver') do |on|
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
      expect(actual_data['resourcePath']).to eq(path)
      expect(actual_data['message']).to start_with('Performed [Remove] on a [JDBC Driver]')
    end

    xit 'Export JDR should retrieve the zip file with the report' do
      wf_server_resource_id = 'Local~~'
      path = CanonicalPath.new(tenant_id: @tenant_id,
                               feed_id: @feed_id,
                               resource_ids: [wf_server_resource_id]).to_s

      actual_data = {}
      @client.export_jdr(path) do |on|
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
      expect(actual_data['resourcePath']).to eq(path)
      expect(actual_data['message']).to start_with('Performed [Export JDR] on')
      expect(actual_data['fileName']).to start_with('jdr_')
    end
  end
end
