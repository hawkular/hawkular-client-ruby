require_relative '../vcr/vcr_setup'
require_relative '../spec_helper'

require 'securerandom'

module Hawkular::Inventory::RSpec
  DEFAULT_VERSION = '0.26.0.Final'
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
        helper_entrypoint(security_context, 'metrics')
      end

      describe 'Inventory Tenants' do
        let(:cassette_name) do |example|
          description = example.description
          description
        end

        around(:each) do |example|
          record("Inventory/#{security_context}/Tenants", credentials, cassette_name, example: example)
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
            @client = setup_inventory_client helper_entrypoint(security_context, 'metrics'), client_options
            WebMock.disable_net_connect!
            VCR.turn_on!
          else
            ::RSpec::Mocks.with_temporary_scope do
              mock_inventory_client(VERSION) unless ENV['VCR_UPDATE'] == '1'
              @client = setup_inventory_client helper_entrypoint(security_context, 'metrics'), client_options
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

        after(:all) do
          require 'fileutils'
          x, y, = @client.version
          FileUtils.rm_rf "#{VCR.configuration.cassette_library_dir}"\
          "/Inventory/#{security_context}/inventory#{x}_#{y}/tmp"
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

        it 'Should list heap metrics for WildFlys' do
          resources = @client.list_resources_for_type(wildfly_type.to_s)
          wild_fly = resources[0]

          metrics = @client.list_metrics_for_resource(wild_fly.path, type: 'GAUGE', match: 'Metrics~Heap')
          expect(metrics.size).to be(3)

          metrics = @client.list_metrics_for_resource(wild_fly.path, match: 'Metrics~Heap')
          expect(metrics.size).to be(3)

          metrics = @client.list_metrics_for_resource(wild_fly.path, type: 'GAUGE')
          expect(metrics.size).to be(8)
        end

        it 'Should list metrics of given metric type' do
          type_path = Hawkular::Inventory::CanonicalPath.new(
            feed_id: feed_id,
            metric_type_id: hawk_escape_id('Platform_File Store_Total Space'))
          metrics = @client.list_metrics_for_metric_type(type_path)

          expect(metrics.size).to be >= 2
        end

        it 'Should have the same requested metric type id' do
          metric_type_id = 'Server Availability~Server Availability'
          type_path = Hawkular::Inventory::CanonicalPath.new(
            feed_id: feed_id,
            metric_type_id: hawk_escape_id(metric_type_id))
          metrics = @client.list_metrics_for_metric_type(type_path)

          expect(metrics.size).to be > 0
          expect(metrics).to all(have_attributes(type_id: metric_type_id))
          expect(metrics.map(&:name)).to all(include('Server Availability'))
        end

        it 'Should return config data of given resource' do
          resource_path = Hawkular::Inventory::CanonicalPath.new(
            feed_id: feed_id,
            resource_ids: [hawk_escape_id('Local~~')])
          config = @client.get_config_data_for_resource(resource_path)

          expect(config['value']['Server State']).to eq('running')
          # expect(config['value']['Product Name']).to eq('Hawkular')
        end

        it 'Should return empty config data of fake resource' do
          resource_path = Hawkular::Inventory::CanonicalPath.new(
            feed_id: feed_id,
            resource_ids: ['fake'])
          config = @client.get_config_data_for_resource(resource_path)

          expect(config).to be_empty
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

        it 'Should get resource type' do
          resource_type = @client.get_resource_type(wildfly_type.to_s)
          expect(resource_type.id).to eq('WildFly Server')
          expect(resource_type.name).to eq('WildFly Server')
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

        it 'Should not find an unknown resource' do
          new_feed_id = 'feed_may_exist'
          path = Hawkular::Inventory::CanonicalPath.new(
            feed_id: new_feed_id,
            resource_ids: [hawk_escape_id('*bla does not exist*')])
          expect { @client.get_resource(path) }
            .to raise_error(Hawkular::BaseClient::HawkularException, /Resource not found/)
        end

        let(:example) do |e|
          e
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
