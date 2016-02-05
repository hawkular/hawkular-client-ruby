require 'hawkular'

# Inventory module provides access to the Hawkular Inventory REST API.
# @see http://www.hawkular.org/docs/rest/rest-inventory.html
#
# @note While Inventory supports 'environments', they are not used currently
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
    # @return [Array<ResourceType>] List of types, that can be empty
    def list_resource_types(feed = nil)
      if feed.nil?
        ret = http_get('/resourceTypes')
      else
        the_feed = hawk_escape feed
        ret = http_get('/feeds/' + the_feed + '/resourceTypes')
      end
      val = []
      ret.each { |rt| val.push(ResourceType.new(rt)) }
      val
    end

    # List the resources for the passed feed and resource type. The representation for
    # resources under a feed are sparse and additional data must be retrived separately.
    # It is possible though to also obtain runtime properties by setting #fetch_properties to true.
    # @param [String] feed The id of the feed the type lives under. Can be nil for feedless types
    # @param [String] type Name of the type to look for. Can be obtained from {ResourceType}.id.
    #   Must not be nil
    # @param [Boolean] fetch_properties Shall additional runtime properties be fetched?
    # @return [Array<Resource>] List of resources. Can be empty
    def list_resources_for_type(feed, type, fetch_properties = false)
      raise 'Type must not be nil' unless type
      the_type = hawk_escape type
      if feed.nil?
        ret = http_get('resourceTypes/' + the_type + '/resources')
      else

        the_feed = hawk_escape feed
        ret = http_get('/feeds/' + the_feed + '/resourceTypes/' + the_type + '/resources')
      end
      val = []
      ret.each do |r|
        if fetch_properties && !feed.nil?
          p = get_config_data_for_resource(r['id'], feed)
          r['properties'] = p['value']
        end
        val.push(Resource.new(r))
      end
      val
    end

    # Retrieve runtime properties for the passed resource
    # @param [String] resource_id Id of the resource to read properties from
    # @param [String] feed Feed of the resource
    # @return [Hash<String,Object] Hash with additional data
    def get_config_data_for_resource(resource_id, feed)
      the_id = hawk_escape resource_id
      the_feed = hawk_escape feed
      http_get('feeds/' + the_feed + '/resources/' + the_id + '/data?dataType=configuration')
    rescue
      {}
    end

    # Obtain the child resources of the passed resource. In case of a WildFly server,
    # those would be Datasources, Deployments and so on.
    # @param [Resource] parent_resource Resource to obtain children from
    # @return [Array<Resource>] List of resources that are children of the given parent resource.
    #   Can be empty
    def list_child_resources(parent_resource)
      the_feed = hawk_escape parent_resource.feed
      the_id = hawk_escape parent_resource.id

      ret = http_get('/feeds/' + the_feed +
                     '/resources/' + the_id + '/children')
      val = []
      ret.each { |r| val.push(Resource.new(r)) }
      val
    end

    # Obtain a list of relationships starting at the passed resource
    # @param [Resource] resource One end of the relationship
    # @return [Array<Relationship>] List of relationships
    def list_relationships(resource)
      the_feed = hawk_escape resource.feed
      the_id = hawk_escape resource.id

      ret = http_get('/feeds/' + the_feed + '/resources/' + the_id + '/relationships')
      val = []
      ret.each { |r| val.push(Relationship.new(r)) }
      val
    rescue
      []
    end

    # Obtain a list of relationships for the passed feed
    # @param [String] feed_id Id of the feed
    # @return [Array<Relationship>] List of relationships
    def list_relationships_for_feed(feed_id)
      the_feed = hawk_escape feed_id
      ret = http_get('/feeds/' + the_feed + '/relationships')
      val = []
      ret.each { |r| val.push(Relationship.new(r)) }
      val
    rescue
      []
    end

    # [15:01:51]  <jkremser>	pilhuhn, this works for me curl -XPOST
    #   -H "Content-Type: application/json"
    #   -u jdoe:password -d
    # '{"id" : "foo", "source": "/t;28026b36-8fe4-4332-84c8-524e173a68bf/f;localhost",
    # "target": "/t;28026b36-8fe4-4332-84c8-524e173a68bf/f;localhost/r;localhost~Local~~/
    #      r;localhost~Local~%2Fsubsystem=hawkular-bus-broker",
    # "name": "isRelatedTo"}'
    #    'http://localhost:8080/hawkular/inventory/feeds/localhost/relationships'
    #
    # def create_relationship(source_resource, target_resource, name, properties = {})
    #   rel = Relationship.new
    #   rel.source_id = source_resource.path
    #   rel.target_id = target_resource.path
    #   rel.name = name
    #   rel.properties = properties
    #
    #   http_post('/feeds/' + source_resource.feed + '/relationships',
    #             rel.to_h)
    # end

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
      the_feed = hawk_escape resource.feed
      the_id = hawk_escape resource.id

      ret = http_get('/feeds/' +
                           the_feed + '/resources/' +
                           the_id + '/metrics')
      val = []
      ret.each do |m|
        metric_new = Metric.new(m)
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
        found = false unless filter[:type] == metric_new.type || filter[:type].nil?
        found = false unless filter[:match].nil? || metric_new.id.include?(filter[:match])
      end
      found
    end
  end

  # A ResourceType is like a class definition for {Resource}s
  # ResourceTypes are currently unique per feed, but one can assume
  # that a two types with the same name of two different feeds are
  # (more or less) the same.
  class ResourceType
    # @return [String] Full path of the type
    attr_reader :path
    # @return [String] Name of the type
    attr_reader :name
    # @return [String] Name of the type
    attr_reader :id
    # @return [String] Feed this type belongs to
    attr_reader :feed
    # @return [String] Environment this Type belongs to - currently unused
    attr_reader :env
    # @return [String] Properties of this type
    attr_reader :properties

    def initialize(rt_hash)
      @id = rt_hash['id']
      @path = rt_hash['path']
      @name = rt_hash['name'] || rt_hash['id']
      @properties = rt_hash['properties']
      @_hash = rt_hash.dup

      tmp = path.split('/')
      tmp.each do |pair|
        (key, val) = pair.split(';')
        case key
        when 'f'
          @feed = val
        when 'e'
          @env = val
        end
      end
    end

    # Returns a hash representation of the resource type
    # @return [Hash<String,Object>] hash of the type
    def to_h
      @_hash.dup
    end
  end

  # A Resource is an instantiation of a {ResourceType}
  class Resource
    # @return [String] Full path of the resource including feed id
    attr_reader :path
    # @return [String] Name of the resource
    attr_reader :name
    # @return [String] Name of the resource
    attr_reader :id
    # @return [String] Name of the feed for this resource
    attr_reader :feed
    # @return [String] Name of the environment for this resource -- currently unused
    attr_reader :env
    # @return [String] Full path of the {ResourceType}
    attr_reader :type_path
    # @return [Hash<String,Object>] Hash with additional, resource specific properties
    attr_reader :properties

    def initialize(res_hash)
      @id = res_hash['id']
      @path = res_hash['path']
      @properties = res_hash['properties'] || {}
      @type_path = res_hash['type']['path']
      @_hash = res_hash

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

    def to_h
      @_hash.deep_dup
    end
  end

  # Definition of a Metric inside the inventory.
  class Metric
    # @return [String] Full path of the metric (definition)
    attr_reader :path
    # @return [String] Name of the metric
    attr_reader :name
    attr_reader :id
    attr_reader :feed
    attr_reader :env
    attr_reader :type
    attr_reader :unit
    # @return [Long] collection interval in seconds
    attr_reader :collection_interval

    def initialize(metric_hash)
      @id = metric_hash['id']
      @path = metric_hash['path']
      @name = metric_hash['name'] || @id
      @_hash = metric_hash.dup

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
      @type = metric_hash['type']['type']
      @unit = metric_hash['type']['unit']
      @collection_interval = metric_hash['collectionInterval']
    end

    def to_h
      @_hash.dup
    end
  end

  # Definition of a Relationship between two entities in Inventory
  class Relationship
    attr_accessor :source_id
    attr_reader :target_id
    attr_reader :properties
    attr_reader :name
    attr_reader :id

    def initialize(hash = {})
      if hash.empty?
        @properties = {}
        return
      end

      @source_id = hash['source']
      @target_id = hash['target']
      @properties = hash['properties']
      @name = hash['name']
      @id = hash['id']
    end

    def to_h
      hash = {}
      hash['source'] = @source_id
      hash['target'] = @target_id
      hash['properties'] = @properties
      hash['name'] = @name
      hash['id'] = @id
      hash
    end
  end
end
