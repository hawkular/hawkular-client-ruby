require 'hawkular/base_client'
# require 'json'

require 'hawkular/inventory/entities_v4'

# Inventory module provides access to the Hawkular Inventory REST API.
module Hawkular::InventoryV4
  # Client class to interact with Hawkular Inventory
  class Client < Hawkular::BaseClient
    attr_reader :version

    # Create a new Inventory Client
    # @param entrypoint [String] base url of Hawkular-inventory - e.g
    #   http://localhost:8080/hawkular/inventory
    # @param credentials [Hash{String=>String}] Hash of username, password, token(optional)
    # @param options [Hash{String=>String}] Additional rest client options
    def initialize(entrypoint = nil, credentials = {}, options = {})
      entrypoint = normalize_entrypoint_url entrypoint, 'hawkular/inventory'
      @entrypoint = entrypoint
      super(entrypoint, credentials, options)
      version = fetch_version_and_status['Implementation-Version']
      @version = version.scan(/\d+/).map(&:to_i)
    end

    # Creates a new Inventory Client
    # @param hash [Hash{String=>Object}] a hash containing base url of Hawkular-inventory - e.g
    #   entrypoint: http://localhost:8080/hawkular/inventory
    # and another sub-hash containing the hash with username[String], password[String], token(optional)
    def self.create(hash)
      fail Hawkular::ArgumentError, 'no parameter ":entrypoint" given' unless hash[:entrypoint]

      hash[:credentials] ||= {}
      hash[:options] ||= {}
      Client.new(hash[:entrypoint], hash[:credentials], hash[:options])
    end

    # Get single resource by id
    # @return Resource the resource
    def resource(id)
      hash = http_get("/resources/#{id}")
      Resource.new(hash)
    end

    # Get resource by id with its complete subtree
    # @return Resource the resource
    def resource_tree(id)
      hash = http_get("/resources/#{id}/tree")
      Resource.new(hash)
    end

    # Get childrens of a resource
    # @return Children of a resource
    def children_resources(parent_id)
      http_get("/resources/#{parent_id}/children")['results'].map { |r| Resource.new(r) }
    end

    # List root resources
    # @return [Array<Resource>] List of resources
    def root_resources
      # FIXME: pagination
      http_get('/resources?root=true')['results'].map { |r| Resource.new(r) }
    end

    # List resources for type
    # @return [Array<Resource>] List of resources
    def resources_for_type(type)
      # FIXME: pagination
      http_get("/resources?typeId=#{type}")['results'].map { |r| Resource.new(r) }
    end

    # Return version and status information for the used version of Hawkular-Inventory
    # @return [Hash{String=>String}]
    #         ('Implementation-Version', 'Built-From-Git-SHA1', 'Status')
    def fetch_version_and_status
      http_get('/status')
    end
  end
end
