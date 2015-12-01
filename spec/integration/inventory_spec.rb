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

      type = 'does not exist'
      types = client.list_resource_types(type)
      expect(type).to eq('does not exist')

      expect(types.size).to be(0)
    end

    it 'Should list WildFlys' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      resources = client.list_resources_for_type('snert', 'WildFly Server')

      expect(resources.size).to be(1)
      wf = resources.first
      expect(wf.properties.size).to be(0)
    end

    it 'Should list WildFlys with props' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      resources = client.list_resources_for_type('snert', 'WildFly Server', true)

      expect(resources.size).to be(1)
      wf = resources.first
      expect(wf.properties['Hostname']).to eq('snert')
    end

    it 'Should List datasources with no props' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      resources = client.list_resources_for_type('snert', 'Datasource', true)

      expect(resources.size).to be(2)
      wf = resources.first
      expect(wf.properties.size).to be(0) # They have no props
    end

    it 'Should list URLs' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      resources = client.list_resources_for_type(nil, 'URL')

      expect(resources.size).to be(1)
      resource = resources[0]
      expect(resource.instance_of? Hawkular::Inventory::Resource).to be_truthy
      expect(resource.properties.size).to be(5)
      expect(resource.properties['url']).to eq('http://bsd.de')
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

    it 'Should list children of WildFly' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      resources = client.list_resources_for_type('snert', 'WildFly Server')
      expect(resources.size).to be(1)

      wild_fly = resources[0]

      metrics = client.list_child_resources(wild_fly)

      expect(metrics.size).to be(21)
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

    # TODO: enable when inventory supports it
    # it 'Should return the version' do
    #   data = @client.get_version_and_status
    #   expect(data).not_to be_nil
    # end
  end
end
