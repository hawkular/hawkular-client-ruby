require_relative '../vcr/vcr_setup'
require_relative '../spec_helper'

require 'securerandom'

include Hawkular::Inventory
include Hawkular::Operations

SKIP_SECURE_CONTEXT = ENV['SKIP_SECURE_CONTEXT'] || '1'

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
      alias_method :helper_host, :host

      let(:host) do
        helper_host(security_context)
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
          c.hook_uris = [helper_host(security_context)]
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
          noop = { operationName: 'noop', resourcePath: '/bla' }
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
          noop = { operationName: 'noop' }
          operation_outcome = {}
          client.invoke_generic_operation(noop) do |on|
            on.success do |_data|
              operation_outcome[:data] = 'should run into error'
            end
            on.failure do |error|
              operation_outcome[:data] = error
            end
          end
          expect(wait_for(operation_outcome)).to eq 'Hash property resourcePath must be specified'
        end

        it 'should bail with hash property error because no callback at all' do
          noop = { operationName: 'noop' }
          expect { client.invoke_generic_operation(noop) }.to raise_error(Hawkular::ArgumentError,
                                                                          'You need to specify error callback')
        end

        it 'should bail with hash property error because no error-callback ' do
          noop = { operationName: 'noop' }
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
          @not_so_random_uuid = 'not_so_random_uuid'
        end

        around(:each) do |example|
          record("Operation/#{security_context}/Helpers", nil, 'get_tenant') do
            ::RSpec::Mocks.with_temporary_scope do
              mock_inventory_client
              @inventory_client = ::Hawkular::Inventory::Client.create(
                options.merge entrypoint: host_with_scheme(host, security_context == SECURE_CONTEXT))
            end
            inventory_client = @inventory_client
            remove_instance_variable(:@inventory_client)
            @tenant_id = 'hawkular'
            record("Operation/#{security_context}/Helpers", { tenant_id: @tenant_id }, 'get_feed') do
              @feed_id = inventory_client.list_feeds[0]
            end
            record("Operation/#{security_context}/Helpers", { tenant_id: @tenant_id, feed_id: @feed_id },
                   'agent_properties') do
              @wf_server_resource_id = 'Local~~'
              agent = installed_agent(inventory_client, @feed_id)
              @agent_immutable = agent_immutable?(agent)
              @agent_path = agent.path
            end
          end
          @bindings = { random_uuid: @random_uuid, tenant_id: @tenant_id, feed_id: @feed_id }
          record_websocket("Operation/#{security_context}/Operation",
                           @bindings,
                           cassette_name,
                           example)
        end

        it 'Add JDBC driver should add the driver' do # Unless it runs in a container
          driver_name = 'CreatedByRubyDriver' + @not_so_random_uuid
          driver_bits = IO.binread("#{File.dirname(__FILE__)}/../resources/driver.jar")
          wf_path = CanonicalPath.new(tenant_id: @tenant_id,
                                      feed_id: @feed_id,
                                      resource_ids: [@wf_server_resource_id]).to_s

          actual_data = {}

          client.add_jdbc_driver(resource_path: wf_path,
                                 driver_jar_name: 'driver.jar',
                                 driver_name: driver_name,
                                 module_name: 'foo.bar' + @not_so_random_uuid, # jboss module
                                 driver_class: 'com.mysql.jdbc.Driver',
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
          wf_server_resource_id = 'Local~~'
          status_war_resource_id = 'Local~%2Fdeployment%3Dhawkular-status.war'
          path = CanonicalPath.new(tenant_id: @tenant_id,
                                   feed_id: @feed_id,
                                   resource_ids: [wf_server_resource_id, status_war_resource_id])

          restart = {
            resource_path: path.to_s,
            deployment_name: 'hawkular-status.war'
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
          expect(actual_data['resourcePath']).to eq(path.up.to_s)
          expect(actual_data['message']).to start_with('Performed [Restart Deployment] on')
        end

        it 'Restart should not be performed if resource path is wrong' do
          wf_server_resource_id = 'Unknown~~'
          wrong_war_resource_id = 'Unknown~%2Fdeployment%3Dnon-existent.war'
          path = CanonicalPath.new(tenant_id: @tenant_id,
                                   feed_id: @feed_id,
                                   resource_ids: [wf_server_resource_id, wrong_war_resource_id])

          restart = {
            resource_path: path.to_s,
            deployment_name: 'non-existent.war'
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
          wf_server_resource_id = 'Local~~'
          status_war_resource_id = 'Local~%2Fdeployment%3Dhawkular-status.war'
          path = CanonicalPath.new(tenant_id: @tenant_id,
                                   feed_id: @feed_id,
                                   resource_ids: [wf_server_resource_id, status_war_resource_id])

          disable = {
            resource_path: path.to_s,
            deployment_name: 'hawkular-status.war'
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
          wf_server_resource_id = 'Local~~'
          wf_path = CanonicalPath.new(tenant_id: @tenant_id,
                                      feed_id: @feed_id,
                                      resource_ids: [wf_server_resource_id]).to_s
          payload = {
            # compulsory fields
            resourcePath: wf_path,
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
            securityDomain: 'other'
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
          wf_server_resource_id = 'Local~~'
          status_war_resource_id = 'Local~%2Fdeployment%3Dhawkular-status.war'
          console_war_resource_id = 'Local~%2Fdeployment%3Dhawkular-wildfly-agent-download.war'
          path1 = CanonicalPath.new(tenant_id: @tenant_id,
                                    feed_id: @feed_id,
                                    resource_ids: [wf_server_resource_id, status_war_resource_id])
          path2 = CanonicalPath.new(tenant_id: @tenant_id,
                                    feed_id: @feed_id,
                                    resource_ids: [wf_server_resource_id, console_war_resource_id])

          restart1 = {
            resource_path: path1.to_s,
            deployment_name: 'hawkular-status.war'
          }

          restart2 = {
            resource_path: path2.to_s,
            deployment_name: 'hawkular-wildfly-agent-download.war'
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
          expect(actual_data['resourcePath']).to eq(path2.up.to_s)
          expect(actual_data['message']).to start_with('Performed [Restart Deployment] on')
        end

        it 'Add deployment should be doable' do
          wf_server_resource_id = 'Local~~'
          app_name = 'sample.war'
          war_file = IO.binread("#{File.dirname(__FILE__)}/../resources/#{app_name}")
          wf_path = CanonicalPath.new(tenant_id: @tenant_id,
                                      feed_id: @feed_id,
                                      resource_ids: [wf_server_resource_id]).to_s

          actual_data = {}
          client.add_deployment(resource_path: wf_path,
                                destination_file_name: app_name,
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
          expect(actual_data['resourcePath']).to eq(wf_path) unless @agent_immutable
          expect(actual_data).to include('Command not allowed because the agent is immutable') if @agent_immutable
        end

        it 'Undeploy deployment should be performed and eventually respond with success' do
          wf_server_resource_id = 'Local~~'
          sample_app_resource_id = 'Local~%2Fdeployment=sample.war'
          path = CanonicalPath.new(tenant_id: @tenant_id,
                                   feed_id: @feed_id,
                                   resource_ids: [wf_server_resource_id, sample_app_resource_id])
          undeploy = {
            resource_path: path.to_s,
            deployment_name: 'sample.war'
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
          wf_server_resource_id = 'Local~~'
          datasource_resource_id = 'Local~%2Fsubsystem%3Ddatasources%2Fdata-source%3DCreatedByRubyDS' + @random_uuid
          path = CanonicalPath.new(tenant_id: @tenant_id,
                                   feed_id: @feed_id,
                                   resource_ids: [wf_server_resource_id, datasource_resource_id])

          operation = {
            resourcePath: path.to_s
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
          expect(actual_data).to include('Command not allowed because the agent is immutable') if @agent_immutable
        end

        it 'Remove JDBC driver should be performed and eventually respond with success' do
          # Unless it runs in a container
          driver_resource_id = 'Local~%2Fsubsystem%3Ddatasources%2Fjdbc-driver%3DCreatedByRubyDriver'
          driver_resource_id << @not_so_random_uuid
          path = CanonicalPath.new(tenant_id: @tenant_id,
                                   feed_id: @feed_id,
                                   resource_ids: [@wf_server_resource_id, driver_resource_id]).to_s

          actual_data = {}
          client.invoke_specific_operation({ resourcePath: path }, 'RemoveJdbcDriver') do |on|
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
          expect(actual_data['resourcePath']).to eq(path) unless @agent_immutable
          expect(actual_data['message']).to start_with(
            'Performed [Remove] on a [JDBC Driver]') unless @agent_immutable
          expect(actual_data).to include('Command not allowed because the agent is immutable') if @agent_immutable
        end

        it 'Export JDR should retrieve the zip file with the report' do
          wf_server_resource_id = 'Local~~'
          path = CanonicalPath.new(tenant_id: @tenant_id,
                                   feed_id: @feed_id,
                                   resource_ids: [wf_server_resource_id]).to_s

          actual_data = {}
          client.export_jdr(path) do |on|
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
          expect(actual_data[:attachments]).to_not be_blank
        end

        it 'Update collection intervals should be performed and eventually respond with success' do
          hash = {
            resourcePath: @agent_path.to_s,
            metricTypes: { 'WildFly Memory Metrics~Heap Max' => 77, 'Unknown~Metric' => 666 },
            availTypes: { 'Server Availability~Server Availability' => 77, 'Unknown~Avail' => 666 }
          }

          actual_data = {}
          client.update_collection_intervals(hash) do |on|
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
          expect(
            actual_data['message']).to start_with('Performed [Update Collection Intervals] on') unless @agent_immutable
          expect(actual_data).to include('Command not allowed because the agent is immutable') if @agent_immutable
        end
      end
    end
  end
end
