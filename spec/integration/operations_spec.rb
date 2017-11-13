require_relative '../vcr/vcr_setup'
require_relative '../spec_helper'

require 'securerandom'

include Hawkular::Inventory
include Hawkular::Operations

SKIP_SECURE_CONTEXT = ENV['SKIP_SECURE_CONTEXT'] || '1'
HOSTS = {
  Secure: 'localhost:8443',
  NonSecure: 'localhost:8080'
}

# examples for operations, it uses the websocket communication
module Hawkular::Operations::RSpec
  NON_SECURE_CONTEXT = :NonSecure
  SECURE_CONTEXT = :Secure

  [NON_SECURE_CONTEXT, SECURE_CONTEXT].each do |security_context|
    next if security_context == SECURE_CONTEXT && SKIP_SECURE_CONTEXT == '1'
    if security_context == NON_SECURE_CONTEXT && ENV['SKIP_NON_SECURE_CONTEXT'] == '1'
      puts 'skipping non secure context'
      next
    end

    context "#{security_context}" do
      let(:host) do
        HOSTS[security_context]
      end

      let(:options) do
        {
          host: host,
          wait_time: WebSocketVCR.live? ? 1.5 : 2,
          use_secure_connection: security_context == SECURE_CONTEXT,
          credentials: credentials,
          options: {
            tenant: 'hawkular'
          }
        }
      end

      let(:example) do |e|
        e
      end

      let(:cassette_name) do |example|
        description = example.description
        description
      end

      let(:client) do
        Client.new(options)
      end

      before(:all) do
        WebSocketVCR.configure do |c|
          c.hook_uris = [HOSTS[security_context]]
        end
      end

      it 'does not connect by default' do
        expect(client.ws).to be nil
      end

      describe 'Operation/Websocket connection' do
        around(:each) do |example|
          if example.metadata[:skip_vcr]
            example.call
          else
            record_websocket("Operation/#{security_context}/Websocket_connection",
                             nil,
                             cassette_name,
                             example)
          end
        end

        it 'connects correctly' do
          ep = host_with_scheme(host, security_context == SECURE_CONTEXT)

          client = Client.new(options.merge entrypoint: ep, host: nil)
          client.connect

          expect(client.ws).not_to be nil
          expect(client.ws).to be_open
        end

        it 'catches errors on connection', :skip_vcr do
          result = {}

          allow(client).to receive(:connect) { fail }

          client.invoke_generic_operation({}) do |on|
            on.success do |_data|
              result[:data] = 'should run into error'
            end
            on.failure do |_error|
              result[:data] = 'fail'
            end
          end

          expect(result[:data]).to eq 'fail'
        end

        it 'should run into error callback' do
          noop = { operationName: 'noop', resourcePath: '/bla', senderRequestId: 'abc' }
          operation_outcome = {}
          client.invoke_generic_operation(noop) do |on|
            on.success do |_data|
              operation_outcome[:data] = 'should run into error'
            end
            on.failure do |_error|
              operation_outcome[:data] = 'fail'
            end
          end
          expect(wait_for(operation_outcome)).to eq 'fail'
        end

        it 'should run into error callback because bad hash parameters' do
          noop = { operationName: 'noop', senderRequestId: 'abc' }
          operation_outcome = {}
          client.invoke_generic_operation(noop) do |on|
            on.success do |_data|
              operation_outcome[:data] = 'should run into error'
            end
            on.failure do |error|
              operation_outcome[:data] = error
            end
          end
          expect(wait_for(operation_outcome)).to eq 'Hash property feedId must be specified'
        end

        it 'should bail with hash property error because no callback at all' do
          noop = { operationName: 'noop', senderRequestId: 'abc' }
          expect { client.invoke_generic_operation(noop) }.to raise_error(Hawkular::ArgumentError,
                                                                          'You need to specify error callback')
        end

        it 'should bail with hash property error because no error-callback ' do
          noop = { operationName: 'noop', senderRequestId: 'abc' }
          expect do
            client.invoke_generic_operation(noop) do |on|
              on.success do |_data|
                fail 'This should have failed'
              end
            end
          end.to raise_error(Hawkular::ArgumentError, 'You need to specify error callback')
        end

        it 'should bail with no host' do
          expect do
            Client.new(options.merge host: nil)
          end.to raise_error(Hawkular::ArgumentError, 'no parameter ":host" or ":entrypoint" given')
        end
      end

      describe 'Operation/Operation' do
        before(:all) do
          @random_uuid = SecureRandom.uuid
          @req_id = '**fixed id for tests**'
          @not_so_random_uuid = 'not_so_random_uuid'
        end

        around(:each) do |example|
          record("Operation/#{security_context}/Helpers", nil, 'get_tenant') do
            ::RSpec::Mocks.with_temporary_scope do
              mock_inventory_client
              @inventory_client = ::Hawkular::Inventory::Client.create(
                options.merge entrypoint: host_with_scheme(host, security_context == SECURE_CONTEXT))
            end
            @tenant_id = 'hawkular'
            record("Operation/#{security_context}/Helpers", { tenant_id: @tenant_id }, 'get_wf_server') do
              @wf_server = @inventory_client.resources(typeId: 'WildFly Server WF10', root: true)[0]
            end
            record("Operation/#{security_context}/Helpers", { tenant_id: @tenant_id }, 'agent_properties') do
              agent = installed_agent(@inventory_client)
              @agent_immutable = agent_immutable?(agent)
              @agent_id = agent.id
            end
          end
          @bindings = { random_uuid: @random_uuid,
                        tenant_id: @tenant_id,
                        feed_id: @wf_server.feed }
          record_websocket("Operation/#{security_context}/Operation",
                           @bindings,
                           cassette_name,
                           example)
        end

        it 'Add JDBC driver should add the driver' do # Unless it runs in a container
          driver_name = 'CreatedByRubyDriver' + @not_so_random_uuid
          driver_bits = IO.binread("#{File.dirname(__FILE__)}/../resources/driver.jar")

          actual_data = {}

          client.add_jdbc_driver(resource_id: @wf_server.id,
                                 feed_id: @wf_server.feed,
                                 driver_jar_name: 'driver.jar',
                                 driver_name: driver_name,
                                 module_name: 'foo.bar' + @not_so_random_uuid, # jboss module
                                 driver_class: 'com.mysql.jdbc.Driver',
                                 sender_request_id: @req_id,
                                 binary_content: driver_bits) do |on|
            on.success do |data|
              actual_data[:data] = data
            end
            on.failure do |error|
              actual_data[:data] = error
              puts 'error callback was called, reason: ' + error.to_s unless @agent_immutable
            end
          end
          actual_data = wait_for actual_data
          expect(actual_data['status']).to eq('OK') unless @agent_immutable
          expect(actual_data['message']).to start_with('Added JDBC Driver') unless @agent_immutable
          expect(actual_data['driverName']).to eq(driver_name) unless @agent_immutable
          expect(actual_data).to include('Command not allowed because the agent is immutable') if @agent_immutable
        end

        it 'Restart should be performed and eventually respond with success' do
          restart = {
            resource_id: @wf_server.id,
            feed_id: @wf_server.feed,
            deployment_name: 'hawkular-status.war',
            sender_request_id: @req_id
          }

          actual_data = {}
          client.restart_deployment(restart) do |on|
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
          expect(actual_data['resourceId']).to eq(@wf_server.id)
          expect(actual_data['destinationFileName']).to eq('hawkular-status.war')
          expect(actual_data['message']).to start_with('Performed [Restart Deployment] on')
        end

        it 'Restart should not be performed if resource path is wrong' do
          restart = {
            resource_id: @wf_server.id,
            feed_id: @wf_server.feed,
            deployment_name: 'non-existent.war',
            sender_request_id: @req_id
          }
          actual_data = {}
          client.restart_deployment(restart) do |on|
            on.success do |_|
              actual_data[:data] = { error: 'the operation should have failed' }
            end
            on.failure do |error|
              actual_data[:data] = { error: error }
            end
          end
          actual_data = wait_for actual_data
          expect(actual_data[:error]).to start_with('Could not perform [Restart Deployment] on a [Application] given')
        end

        it 'Disable should be performed and eventually respond with success' do
          disable = {
            resource_id: @wf_server.id,
            feed_id: @wf_server.feed,
            deployment_name: 'hawkular-status.war',
            sender_request_id: @req_id
          }
          actual_data = {}
          client.disable_deployment(disable) do |on|
            on.success do |data|
              actual_data[:data] = data
            end
            on.failure do |error|
              actual_data[:data] = error
              puts 'error callback was called, reason: ' + error.to_s unless @agent_immutable
            end
          end
          actual_data = wait_for actual_data
          expect(actual_data['status']).to eq('OK') unless @agent_immutable
          expect(actual_data['message']).to start_with('Performed [Disable Deployment] on') unless @agent_immutable
          expect(actual_data).to include('Command not allowed because the agent is immutable') if @agent_immutable
        end

        it 'Add non-XA datasource should be doable' do
          payload = {
            # compulsory fields
            resourceId: @wf_server.id,
            feedId: @wf_server.feed,
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
            securityDomain: 'other',
            senderRequestId: @req_id
            # xaDataSourceClass: 'clazz' for xa DS
          }

          actual_data = {}
          client.add_datasource(payload) do |on|
            on.success do |data|
              actual_data[:data] = data
            end
            on.failure do |error|
              actual_data[:data] = error
              puts 'error callback was called, reason: ' + error.to_s unless @agent_immutable
            end
          end
          actual_data = wait_for actual_data
          expect(actual_data['status']).to eq('OK') unless @agent_immutable
          expect(actual_data['message']).to start_with('Added Datasource') unless @agent_immutable
          expect(actual_data['xaDatasource']).to be_falsey unless @agent_immutable
          expect(actual_data['datasourceName']).to eq(payload[:datasourceName]) unless @agent_immutable
          expect(actual_data['resourcePath']).to eq(payload[:resourcePath]) unless @agent_immutable
          expect(actual_data).to include('Command not allowed because the agent is immutable') if @agent_immutable
        end

        it 'Add XA datasource should be doable' do
          payload = {
            # compulsory fields
            resourceId: @wf_server.id,
            feedId: @wf_server.feed,
            xaDatasource: true,
            datasourceName: 'CreatedByRubyDSXA' + @random_uuid,
            jndiName: 'java:jboss/datasources/CreatedByRubyDSXA' + @random_uuid,
            driverName: 'h2',
            xaDataSourceClass: 'org.h2.jdbcx.JdbcDataSource',
            # this is probably a bug (driver class should be already defined in driver)
            driverClass: 'org.h2.Driver',
            connectionUrl: 'dbc:h2:mem:ruby;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE',

            # optional
            datasourceProperties: {
              someKey: 'someValue'
            },
            userName: 'sa',
            password: 'sa',
            securityDomain: 'other',
            senderRequestId: @req_id
          }

          actual_data = {}
          client.add_datasource(payload) do |on|
            on.success do |data|
              actual_data[:data] = data
            end
            on.failure do |error|
              actual_data[:data] = error
              puts 'error callback was called, reason: ' + error.to_s unless @agent_immutable
            end
          end
          actual_data = wait_for actual_data
          expect(actual_data['status']).to eq('OK') unless @agent_immutable
          expect(actual_data['message']).to start_with('Added Datasource') unless @agent_immutable
          expect(actual_data['xaDatasource']).to be_truthy unless @agent_immutable
          expect(actual_data['datasourceName']).to eq(payload[:datasourceName]) unless @agent_immutable
          expect(actual_data['resourcePath']).to eq(payload[:resourcePath]) unless @agent_immutable
          expect(actual_data).to include('Command not allowed because the agent is immutable') if @agent_immutable
        end

        it 'Restart can be run multiple times in parallel' do
          restart1 = {
            resource_id: @wf_server.id,
            feed_id: @wf_server.feed,
            deployment_name: 'hawkular-status.war',
            sender_request_id: @req_id
          }

          restart2 = {
            resource_id: @wf_server.id,
            feed_id: @wf_server.feed,
            deployment_name: 'hawkular-prometheus-alerter.war',
            sender_request_id: 'another_id'
          }

          # run the first operation w/o registering the callback
          client.restart_deployment(restart1)

          actual_data = {}
          # run the 2nd operation with 2 callback blocks (the happy path and the less happy path)
          client.restart_deployment(restart2) do |on|
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
          expect(actual_data['senderRequestId']).to eq('another_id')
          expect(actual_data['resourceId']).to eq(@wf_server.id)
          expect(actual_data['destinationFileName']).to eq('hawkular-prometheus-alerter.war')
          expect(actual_data['message']).to start_with('Performed [Restart Deployment] on')
        end

        it 'Add deployment should be doable' do
          app_name = 'sample.war'
          war_file = IO.binread("#{File.dirname(__FILE__)}/../resources/#{app_name}")
          actual_data = {}
          client.add_deployment(resource_id: @wf_server.id,
                                feed_id: @wf_server.feed,
                                destination_file_name: app_name,
                                sender_request_id: @req_id,
                                binary_content: war_file) do |on|
            on.success do |data|
              actual_data[:data] = data
            end
            on.failure do |error|
              actual_data[:data] = error
              puts 'error callback was called, reason: ' + error.to_s unless @agent_immutable
            end
          end
          actual_data = wait_for actual_data
          expect(actual_data['status']).to eq('OK') unless @agent_immutable
          expect(actual_data['message']).to start_with('Performed [Deploy] on') unless @agent_immutable
          expect(actual_data['destinationFileName']).to eq(app_name) unless @agent_immutable
          expect(actual_data['resourceId']).to eq(@wf_server.id) unless @agent_immutable
          expect(actual_data).to include('Command not allowed because the agent is immutable') if @agent_immutable
        end

        it 'Undeploy deployment should be performed and eventually respond with success' do
          undeploy = {
            resource_id: @wf_server.id,
            feed_id: @wf_server.feed,
            deployment_name: 'sample.war',
            sender_request_id: @req_id
          }
          actual_data = {}
          client.undeploy(undeploy) do |on|
            on.success do |data|
              actual_data[:data] = data
            end
            on.failure do |error|
              actual_data[:data] = error
              puts 'error callback was called, reason: ' + error.to_s unless @agent_immutable
            end
          end
          actual_data = wait_for actual_data
          expect(actual_data['status']).to eq('OK') unless @agent_immutable
          expect(actual_data['message']).to start_with('Performed [Undeploy] on') unless @agent_immutable
          expect(actual_data).to include('Command not allowed because the agent is immutable') if @agent_immutable
        end

        it 'Remove datasource should be performed and eventually respond with success' do
          ds = nil
          unless @agent_immutable
            record("Operation/#{security_context}/Helpers", nil, 'get_datasource') do
              ds = @inventory_client.children_resources(@wf_server.id)
                   .select { |r| r.name.include? "CreatedByRubyDS#{@random_uuid}" }[0]
                   .id
            end
          end
          operation = {
            resourceId: ds,
            feedId: @wf_server.feed,
            senderRequestId: @req_id
          }

          actual_data = {}
          client.invoke_specific_operation(operation, 'RemoveDatasource') do |on|
            on.success do |data|
              actual_data[:data] = data
            end
            on.failure do |error|
              actual_data[:data] = error
              puts 'error callback was called, reason: ' + error.to_s unless @agent_immutable
            end
          end
          actual_data = wait_for actual_data
          expect(actual_data['status']).to eq('OK') unless @agent_immutable
          expect(actual_data['message']).to start_with('Performed [Remove] on') unless @agent_immutable
          expect(actual_data['serverRefreshIndicator']).to eq('RELOAD-REQUIRED') unless @agent_immutable
        end unless @agent_immutable

        it 'Remove JDBC driver should be performed and eventually respond with success' do
          # Unless it runs in a container
          driver = nil
          unless @agent_immutable
            record("Operation/#{security_context}/Helpers", nil, 'get_driver') do
              driver = @inventory_client.children_resources(@wf_server.id)
                       .select { |r| r.name.include? "CreatedByRubyDriver#{@not_so_random_uuid}" }[0]
                       .id
            end
          end
          operation = {
            resourceId: driver,
            feedId: @wf_server.feed,
            senderRequestId: @req_id
          }

          actual_data = {}
          client.invoke_specific_operation(operation, 'RemoveJdbcDriver') do |on|
            on.success do |data|
              actual_data[:data] = data
            end
            on.failure do |error|
              actual_data[:data] = error
              puts 'error callback was called, reason: ' + error.to_s unless @agent_immutable
            end
          end
          actual_data = wait_for actual_data
          expect(actual_data['status']).to eq('OK') unless @agent_immutable
          expect(actual_data['resource_id']).to eq(driver_resource_id) unless @agent_immutable
          expect(actual_data['message']).to start_with(
            'Performed [Remove] on a [JDBC Driver]') unless @agent_immutable
        end

        it 'Export JDR should retrieve the zip file with the report' do
          actual_data = {}
          client.export_jdr(@wf_server.id, @wf_server.feed, false, @req_id) do |on|
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
          expect(actual_data['resourceId']).to eq(@wf_server.id)
          expect(actual_data['message']).to start_with('Performed [Export JDR] on')
          expect(actual_data['fileName']).to start_with('jdr_')
          expect(actual_data[:attachments]).to_not be_blank
        end
      end
    end
  end
end
