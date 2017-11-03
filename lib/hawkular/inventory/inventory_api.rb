require 'hawkular/base_client'

require 'hawkular/inventory/entities'

# Inventory module provides access to the Hawkular Inventory REST API.
module Hawkular::Inventory
  # Client class to interact with Hawkular Inventory
  class Client < Hawkular::BaseClient
    attr_reader :version

    # Create a new Inventory Client
    # @param entrypoint [String] base url of Hawkular-inventory - e.g
    #   http://localhost:8080/hawkular/inventory
    # @param credentials [Hash{String=>String}] Hash of username, password, token(optional)
    # @param options [Hash{String=>String}] Additional rest client options
    def initialize(entrypoint = nil, credentials = {}, options = {}, page_size = nil)
      entrypoint = normalize_entrypoint_url entrypoint, 'hawkular/inventory'
      @entrypoint = entrypoint
      super(entrypoint, credentials, options)
      version = fetch_version_and_status['Implementation-Version']
      @version = version.scan(/\d+/).map(&:to_i)
      @page_size = page_size || 100
    end

    # Creates a new Inventory Client
    # @param hash [Hash{String=>Object}] a hash containing base url of Hawkular-inventory - e.g
    #   entrypoint: http://localhost:8080/hawkular/inventory
    # and another sub-hash containing the hash with username[String], password[String], token(optional)
    def self.create(hash)
      fail Hawkular::ArgumentError, 'no parameter ":entrypoint" given' unless hash[:entrypoint]

      hash[:credentials] ||= {}
      hash[:options] ||= {}
      Client.new(hash[:entrypoint], hash[:credentials], hash[:options], hash[:page_size])
    end

    # Get single resource by id
    # @return Resource the resource
    def resource(id)
      hash = http_get(url('/resources/%s', id))
      Resource.new(hash)
    end

    # Get resource by id with its complete subtree
    # @return Resource the resource
    def resource_tree(id)
      hash = http_get(url('/resources/%s/tree', id))
      Resource.new(hash)
    end

    # Get childrens of a resource
    # @return Children of a resource
    def children_resources(parent_id)
      http_get(url('/resources/%s/children', parent_id))['results'].map { |r| Resource.new(r) }
    end

    # Get parent of a resource
    # @return Resource the parent resource, or nil if the provided ID referred to a root resource
    def parent(id)
      hash = http_get(url('/resources/%s/parent', id))
      Resource.new(hash) if hash
    end

    # List root resources
    # @return [Enumeration<Resource>] Lazy-loaded Enumeration of resources
    def root_resources
      resources root: 'true'
    end

    # List resources
    # @param [Hash] filter options to filter the resource list
    # @option filter :root If truthy, only get root resources
    # @option filter :feedId Filter by feed id
    # @option filter :typeId Filter by type id
    # @return [Enumeration<Resource>] Lazy-loaded Enumeration of resources
    def resources(filter = {})
      filter[:root] = !filter[:root].nil? if filter.key? :root
      filter[:maxResults] = @page_size

      fetch_func = lambda do |offset|
        filter[:startOffSet] = offset
        filter_query = '?' + filter.keys.join('=%s&') + '=%s' unless filter.empty?
        http_get(url("/resources#{filter_query}", *filter.values))
      end
      ResultFetcher.new(fetch_func).map { |r| Resource.new(r) }
    end

    # List resources for type
    # @return [Enumeration<Resource>] Lazy-loaded Enumeration of resources
    def resources_for_type(type)
      resources typeId: type
    end

    # Return version and status information for the used version of Hawkular-Inventory
    # @return [Hash{String=>String}]
    #         ('Implementation-Version', 'Built-From-Git-SHA1', 'Status')
    def fetch_version_and_status
      http_get('/status')
    end
  end

  # Lazy fetching results, based on Inventory "ResultSet" model
  class ResultFetcher
    include Enumerable

    def initialize(fetcher)
      @fetcher = fetcher
    end

    def each
      offset = 0
      loop do
        result_set = @fetcher.call(offset)
        results = result_set['results']
        results.each { |r| yield(r) }
        offset += results.length
        break if offset >= result_set['resultSize']
      end
    end
  end
end
