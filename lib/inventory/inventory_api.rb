require 'hawkular'

# Inventory module provides access to the Hawkular Inventory REST API.
# @see http://www.hawkular.org/docs/rest/rest-inventory.html
#
# @note While Inventory supports 'environements', they are not used currently
#   and thus set to 'test' as default value.
module Hawkular::Inventory
  # Client class to interact with Hawkular Inventory
  class InventoryClient < Hawkular::BaseClient
    # Create a new Inventory Client
    # @param entrypoint [String] base url of Hawkular-inventory - e.g
    #   http://localhost:8080/hawkular/inventory
    # @param credentials [Hash{String=>String}] Hash of username, password, token(optional)
    def initialize(entrypoint = nil, credentials = {})
      @entrypoint = entrypoint

      super(entrypoint, credentials)
    end

    # Retrieve the tenant id for the passed credentials.
    # If no credentials are passed, the ones from the constructor are used
    # @param credentials [Hash{String=>String}] Hash of username, password, token(optional)
    # @return [String] tenant id
    def get_tenant(credentials = {})
      creds = credentials.empty? ? @credentials : credentials
      auth_header = { Authorization: base_64_credentials(creds) }

      ret = http_get('/tenant', auth_header)

      ret['id']
    end

    # TODO: revisit and potentially move to Base ?
    def impersonate(credentials = {})
      @tenant = get_tenant(credentials)
      @options[:tenant] = @tenant
    end

    # List feeds in the system
    # @return [Array<String>] List of feed ids
    def list_feeds(_environment = 'test')
      ret = http_get('feeds')
      val = []
      ret.each { |f| val.push(f['id']) }
      val
    end

    # List resource types. If no need is given all types are listed
    # @param [String] feed The id of the feed the type lives under. Can be nil for feedless types
    # @param [String] environment the environment to use
    # @return [Array<ResourceType>] List of types, that can be empty
    def list_resource_types(feed = nil, environment = 'test')
      if feed.nil?
        ret = http_get('/resourceTypes')
      else
        ret = http_get('/' + environment + '/' + feed + '/resourceTypes')
      end
      val = []
      ret.each { |rt| val.push(ResourceType.new(rt['path'], rt['id'])) }
      val
    end

    # List the resources for the passed feed and resource type.
    # @param [String] feed The id of the feed the type lives under. Can be nil for feedless types
    # @param [String] type Name of the type to look for. Can be obtained from ResourceType.id
    # @param [String] environment the environment to use
    # @return [Array<Resource>] List of resources. Can be empty
    def list_resources_for_type(feed, type, environment = 'test')
      if feed.nil?
        ret = http_get('resourceTypes/' + type + '/resources')
      else
        ret = http_get('/' + environment + '/' + feed + '/resourceTypes/' + type + '/resources')
      end
      val = []
      ret.each { |r| val.push(Resource.new(r)) }
      val
    end

    # def list_metrics_for_resource_type
    #   # TODO implement me
    # end

    # List metric (definitions) for the passed resource. It is possible to filter down the
    #   result by a filter to only return a subset. The
    # @param [Resource] resource
    # @param [Hash{Symbol=>String}] filter for 'type' and 'match'
    #   Metric type can be one of 'GAUGE', 'COUNTER', 'AVAILABILITY'. If a key is missing
    #   it will not be used for filtering
    # @return [Aray<Metric>] List of metrics that can be empty.
    # @example
    #    # Filter by type and match on metrics id
    #    client.list_metrics_for_resource(wild_fly, type: 'GAUGE', match: 'Metrics~Heap')
    #    # Filter by type only
    #    client.list_metrics_for_resource(wild_fly, type: 'COUNTER')
    #    # Don't filter, return all metric definitions
    #    client.list_metrics_for_resource(wild_fly)
    def list_metrics_for_resource(resource, filter = {})
      ret = http_get('/' + resource.env + '/' +
                           resource.feed + '/resources/' +
                           resource.id + '/metrics')
      val = []
      ret.each do |m|
        metric_new = Metric.new(m['path'], m['id'], m['type'])
        found = should_include?(metric_new, filter)
        val.push(metric_new) if found
      end
      val
    end

    private

    def should_include?(metric_new, filter)
      found = true
      if filter.empty?
        found = true
      else
        found = false unless filter[:type] == (metric_new.type) || filter[:type].nil?
        found = false unless filter[:match].nil? || metric_new.id.include?(filter[:match])
      end
      found
    end
  end

  class ResourceType
    attr_reader :path, :name, :id, :feed, :env

    def initialize(path, id)
      @id = id
      @path = path

      tmp = path.split('/')
      tmp.each do |pair|
        (key, val) = pair.split(';')
        case key
        when 'f'
          @feed = val
        when 'e'
          @env = val
        when 'n'
          @name = val.nil? ? id : val
        end
      end
    end
  end

  class Resource
    attr_reader :path, :name, :id, :feed, :env, :type_path
    attr_reader :properties

    def initialize(res_hash)
      @id = res_hash['id']
      @path = res_hash['path']
      @properties = res_hash['properties']
      @type_path = res_hash['type']['path']

      tmp = @path.split('/')
      tmp.each do |pair|
        (key, val) = pair.split(';')
        case key
        when 'f'
          @feed = val
        when 'e'
          @env = val
        when 'n'
          @name = val.nil? ? id : val
        end
      end
      self
    end
  end

  class Metric
    attr_reader :path, :name, :id, :feed, :env, :type, :unit

    def initialize(path, id, res_type)
      @id = id
      @path = path

      tmp = path.split('/')
      tmp.each do |pair|
        (key, val) = pair.split(';')
        case key
        when 'f'
          @feed = val
        when 'e'
          @env = val
        when 'n'
          @name = val.nil? ? id : val
        end
      end
      @type = res_type['type']
      @unit = res_type['unit']
    end
  end
end
