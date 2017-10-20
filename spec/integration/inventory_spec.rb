require_relative '../vcr/vcr_setup'
require_relative '../spec_helper'

require 'securerandom'

module Hawkular::Inventory::RSpec
  DEFAULT_VERSION = '0.9.8.Final'
  VERSION = ENV['INVENTORY_VERSION'] || DEFAULT_VERSION
  HOST = 'http://localhost:8080'

  describe 'Inventory' do
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
        mock_inventory_client DEFAULT_VERSION
        @client = Hawkular::Client.new(entrypoint: HOST, credentials: @creds, options: {}).inventory
      end
      @state = {
        hostname: 'localhost.localdomain',
        feed: nil
      }
    end

    around(:each) do |example|
      run_for = example.metadata[:run_for]
      if run_for.nil? || run_for.empty? || run_for.include?(metrics_context)
        @random_id = SecureRandom.uuid
        if example.metadata[:skip_auto_vcr]
          example.run
        else
          record('Inventory', {}, cassette_name, example: example)
        end
      end
    end

    after(:all) do
      record_cleanup('Inventory')
    end

    it 'Should list root resources' do
      res = @client.root_resources
      expect(res.size).to be(4)
      expect(res.map { |r| r.type.id }).to include(
        'Runtime MBean', 'WildFly Server', 'Platform_Operating System', 'Hawkular WildFly Agent')
      # Children are not loaded
      expect(res.map(&:children)).to eq([nil, nil, nil, nil])
    end

    it 'Should get by type' do
      res = @client.resources_for_type('Memory Pool MBean')
      expect(res.size).to be(6)
      expect(res.map(&:name)).to include(
        'JMX [Local JMX] MemoryPool Metaspace', 'JMX [Local JMX] MemoryPool PS Eden Space')
    end

    it 'Should get resource' do
      id = @client.root_resources.find { |r| r.name == 'JMX [Local JMX][Runtime]' }.id
      res = @client.resource(id)
      expect(res).not_to be_nil
      expect(res.name).to eq('JMX [Local JMX][Runtime]')
      expect(res.type).not_to be_nil
      expect(res.type.id).to eq('Runtime MBean')
      expect(res.children).to be_nil
      expect(res.metrics).not_to be_nil
      expect(res.metrics.size).to eq(4)
      expect(res.metrics.map(&:name)).to include('VM Uptime', 'Used Heap Memory')
      expect(res.metrics.map(&:unit)).to include('MILLISECONDS', 'BYTES')
    end

    it 'Should get subtree' do
      id = @client.root_resources.find { |r| r.name == 'JMX [Local JMX][Runtime]' }.id
      res = @client.resource_tree(id)
      expect(res).not_to be_nil
      expect(res.name).to eq('JMX [Local JMX][Runtime]')
      expect(res.type).not_to be_nil
      expect(res.type.id).to eq('Runtime MBean')
      expect(res.children).not_to be_nil
      expect(res.children.size).to eq(6)
      expect(res.children.map(&:name)).to include(
        'JMX [Local JMX] MemoryPool Metaspace', 'JMX [Local JMX] MemoryPool PS Eden Space')
    end

    it 'Should get children' do
      id = @client.root_resources.find { |r| r.name == 'JMX [Local JMX][Runtime]' }.id
      res = @client.children_resources(id)
      expect(res).not_to be_nil
      expect(res.size).to eq(6)
      expect(res.map(&:name)).to include(
        'JMX [Local JMX] MemoryPool Metaspace', 'JMX [Local JMX] MemoryPool PS Eden Space')
      expect(res.map(&:parent_id)).to eq([id, id, id, id, id, id])
    end

    it 'Should get parent' do
      parent_id = @client.root_resources.find { |r| r.name == 'JMX [Local JMX][Runtime]' }.id
      child_id = @client.children_resources(parent_id)[0].id
      res = @client.parent(child_id)
      expect(res).not_to be_nil
      expect(res.id).to eq(parent_id)
      expect(res.name).to eq('JMX [Local JMX][Runtime]')
      expect(res.parent_id).to be_nil
    end

    it 'Should return the version' do
      data = @client.fetch_version_and_status
      expect(data).not_to be_nil
    end
  end
end
