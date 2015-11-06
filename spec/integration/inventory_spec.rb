require "#{File.dirname(__FILE__)}/../vcr/vcr_setup"
require "#{File.dirname(__FILE__)}/../spec_helper"

module Hawkular::Inventory::RSpec
  INVENTORY_BASE = 'http://localhost:8080/hawkular/inventory'
  describe 'Tenants', :vcr do
    it 'Should Get Tenant For Explicit Credentials' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)

      tenant = client.get_tenant(creds)

      expect tenant.nil?
      expect tenant.eql?('28026b36-8fe4-4332-84c8-524e173a68bf')
    end

    it 'Should Get Tenant For Implicit Credentials' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)

      tenant = client.get_tenant

      expect tenant.nil?

      expect tenant.eql?('28026b36-8fe4-4332-84c8-524e173a68bf')
    end
  end

  describe 'Inventory', :vcr do
    it 'Should list feeds' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      feeds = client.list_feeds

      expect(feeds.size).to be(1)
    end

    it 'Should list types without feed' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      types = client.list_resource_types

      expect(types.size).to be(17)
    end

    it 'Should list types with feed' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      types = client.list_resource_types('snert')

      expect(types.size).to be(16)
    end

    it 'Should list types with bad feed' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      types = client.list_resource_types('does not exist')

      expect(types.size).to be(0)
    end

    it 'Should list WildFlys' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      resources = client.list_resources_for_type('snert', 'WildFly Server')

      expect(resources.size).to be(1)
    end

    it 'Should list metrics for WildFlys' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      resources = client.list_resources_for_type('snert', 'WildFly Server')
      expect(resources.size).to be(1)

      wild_fly = resources[0]

      metrics = client.list_metrics_for_resource(wild_fly)

      expect(metrics.size).to be(14)
    end

    it 'Should list heap metrics for WildFlys' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      resources = client.list_resources_for_type('snert', 'WildFly Server')
      expect(resources.size).to be(1)

      wild_fly = resources[0]

      metrics = client.list_metrics_for_resource(wild_fly, type: 'GAUGE', match: 'Metrics~Heap')
      expect(metrics.size).to be(3)

      metrics = client.list_metrics_for_resource(wild_fly, match: 'Metrics~Heap')
      expect(metrics.size).to be(3)

      metrics = client.list_metrics_for_resource(wild_fly, type: 'GAUGE')
      expect(metrics.size).to be(10)
    end
  end
end
