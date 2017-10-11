require_relative '../vcr/vcr_setup'
require_relative '../spec_helper'

require 'securerandom'

module Hawkular::InventoryV4::RSpec
  DEFAULT_VERSION = '0.9.8.Final'
  VERSION = ENV['INVENTORY_VERSION'] || DEFAULT_VERSION

  describe 'Inventory v4' do
    before(:all) do
      @client = Hawkular::Client.new(entrypoint: 'http://localhost:8080', options: {}).inventory_v4
    end

    it 'Should list root resources' do
      res = @client.root_resources
      expect(res.size).to be(4)
      expect(res.map { |r| r.type.id }).to eq(
        ['Runtime MBean', 'WildFly Server', 'Platform_Operating System', 'Hawkular WildFly Agent'])
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

    it 'Should return the version' do
      data = @client.fetch_version_and_status
      expect(data).not_to be_nil
    end
  end
end
