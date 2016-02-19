require "#{File.dirname(__FILE__)}/../vcr/vcr_setup"
require "#{File.dirname(__FILE__)}/../spec_helper"

# rubocop:disable Style/GlobalVars
$state = { hostname: 'localhost.localdomain' }

module Hawkular::Inventory::RSpec
  INVENTORY_BASE = 'http://localhost:8080/hawkular/inventory'
  describe 'Tenants', :vcr do
    it 'Should Get Tenant For Explicit Credentials' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)

      tenant = client.get_tenant(creds)

      expect(tenant).to eq('28026b36-8fe4-4332-84c8-524e173a68bf')
    end

    it 'Should Get Tenant For Implicit Credentials' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)

      tenant = client.get_tenant

      expect(tenant).to eq('28026b36-8fe4-4332-84c8-524e173a68bf')
    end
  end

  describe 'Inventory', vcr: { decode_compressed_response: true } do
    it 'Should list feeds' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      feeds = client.list_feeds

      expect(feeds.size).to be(1)
      $state[:feed_id] = feeds[0]
    end

    it 'Should list all the resource types' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      types = client.list_resource_types

      expect(types.size).to be(19)
    end

    it 'Should list types with feed' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      types = client.list_resource_types($state[:feed_id])

      expect(types.size).to be(18)
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

      resources = client.list_resources_for_type($state[:feed_id], 'WildFly Server')

      expect(resources.size).to be(1)
      wf = resources.first
      expect(wf.properties.size).to be(0)
    end

    it 'Should list WildFlys with props' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      resources = client.list_resources_for_type($state[:feed_id], 'WildFly Server', true)

      expect(resources.size).to be(1)
      wf = resources.first
      expect(wf.properties['Hostname']).to eq($state[:hostname])
    end

    it 'Should List datasources with no props' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      resources = client.list_resources_for_type($state[:feed_id], 'Datasource', true)

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
      expect(resource.properties.size).to be(6)
      expect(resource.properties['url']).to eq('http://bsd.de')
    end

    it 'Should list metrics for WildFlys' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      resources = client.list_resources_for_type($state[:feed_id], 'WildFly Server')
      expect(resources.size).to be(1)

      wild_fly = resources[0]

      metrics = client.list_metrics_for_resource(wild_fly)

      expect(metrics.size).to be(14)
    end

    it 'Should list children of WildFly' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      resources = client.list_resources_for_type($state[:feed_id], 'WildFly Server')
      expect(resources.size).to be(1)

      wild_fly = resources[0]

      children = client.list_child_resources(wild_fly)

      expect(children.size).to be(21)
    end

    it 'Should list recursive children of WildFly' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      resources = client.list_resources_for_type($state[:feed_id], 'WildFly Server')
      wild_fly = resources[0]

      children = client.list_child_resources(wild_fly, recursive: true)

      expect(children.size).to be(211)
    end

    it 'Should list relationships of WildFly' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      resources = client.list_resources_for_type($state[:feed_id], 'WildFly Server')
      wild_fly = resources[0]

      rels = client.list_relationships(wild_fly)

      expect(rels.size).to be(59)
    end

    it 'Should list heap metrics for WildFlys' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      resources = client.list_resources_for_type($state[:feed_id], 'WildFly Server')
      expect(resources.size).to be(1)

      wild_fly = resources[0]

      metrics = client.list_metrics_for_resource(wild_fly, type: 'GAUGE', match: 'Metrics~Heap')
      expect(metrics.size).to be(3)

      metrics = client.list_metrics_for_resource(wild_fly, match: 'Metrics~Heap')
      expect(metrics.size).to be(3)

      metrics = client.list_metrics_for_resource(wild_fly, type: 'GAUGE')
      expect(metrics.size).to be(8)
    end

    it 'Should list metrics of given metric type' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      metrics = client.list_metrics_for_metric_type($state[:feed_id], 'Total Space')

      expect(metrics.size).to be(7)
    end

    it 'Should list metrics of given resource type' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Inventory::InventoryClient.new(INVENTORY_BASE, creds)
      client.impersonate

      metrics = client.list_metrics_for_resource_type($state[:feed_id], 'WildFly Server')

      expect(metrics.size).to be(14)
    end

    # TODO: enable when inventory supports it
    # it 'Should return the version' do
    #   data = @client.get_version_and_status
    #   expect(data).not_to be_nil
    # end
  end
end
# rubocop:enable Style/GlobalVars
