require_relative '../vcr/vcr_setup'
require_relative '../spec_helper'

require 'securerandom'

module Hawkular::InventoryV4::RSpec
  DEFAULT_VERSION = '0.9.8.Final'
  VERSION = ENV['INVENTORY_VERSION'] || DEFAULT_VERSION

  SKIP_SECURE_CONTEXT = ENV['SKIP_SECURE_CONTEXT'] || '1'

  URL_RESOURCE = 'http://bsd.de'

  NON_SECURE_CONTEXT = :NonSecure
  SECURE_CONTEXT = :Secure

  [NON_SECURE_CONTEXT, SECURE_CONTEXT].each do |security_context|
    next if security_context == SECURE_CONTEXT && SKIP_SECURE_CONTEXT == '1'

    context "#{security_context}" do
      include Hawkular::InventoryV4

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
          record("InventoryV4/#{security_context}/Tenants", credentials, cassette_name, example: example)
        end
      end

      describe 'Inventory Connection' do
        let(:cassette_name) do |example|
          description = example.description
          description
        end

        around(:each) do |example|
          record("InventoryV4/#{security_context}/Connection", credentials, cassette_name, example: example)
        end

        it 'Should err on bad credentials' do
          @creds = credentials
          @creds[:username] << @creds[:password]
          VCR.eject_cassette
          record("InventoryV4/#{security_context}/Connection", @creds, cassette_name) do
            expect do
              Hawkular::Inventory::Client.create(entrypoint: entrypoint, credentials: @creds)
            end.to raise_error(Hawkular::BaseClient::HawkularException, 'Unauthorized')
          end
        end
      end

      describe 'Inventory v4' do
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

          record("InventoryV4/#{security_context}/inventory_#{x}_#{y}", @state.clone, 'Helpers/wait_for_wildfly') do
            wait_while do
              @client.list_root_resources().length < 1
            end
          end if ENV['RUN_ON_LIVE_SERVER'] == '1'

          # create 1 URL resource and its metrics
          record("InventoryV4/#{security_context}/inventory_#{x}_#{y}", @state.clone, 'Helpers/create_url') do
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
          "/InventoryV4/#{security_context}/inventory#{x}_#{y}/tmp"
        end

        let(:cassette_name) do |example|
          description = example.description
          description
        end

        around(:each) do |example|
          major, minor, = @client.version
          record("InventoryV4/#{security_context}/inventory_#{major}_#{minor}", @state, cassette_name, example: example)
        end

        it 'Should list root resources' do
        end

        it 'Should return the version' do
          data = @client.fetch_version_and_status
          expect(data).not_to be_nil
        end
      end
    end
  end
end
