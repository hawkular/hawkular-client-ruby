require 'hawkular/base_client'
require 'websocket-client-simple'
require 'json'

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
    # @param options [Hash{String=>String}] Additional rest client options
    def initialize(entrypoint = nil, credentials = {}, options = {})
      @entrypoint = entrypoint
      super(entrypoint, credentials, options)
    end

    # Creates a new Inventory Client
    # @param hash [Hash{String=>Object}] a hash containing base url of Hawkular-inventory - e.g
    #   entrypoint: http://localhost:8080/hawkular/inventory
    # and another sub-hash containing the hash with username[String], password[String], token(optional)
    def self.create(hash)
      hash[:entrypoint] ||= 'http://localhost:8080/hawkular/inventory'
      hash[:credentials] ||= {}
      hash[:options] ||= {}
      InventoryClient.new(hash[:entrypoint], hash[:credentials], hash[:options])
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
    def impersonate!(credentials = {})
      @tenant = get_tenant(credentials)
      @options[:tenant] = @tenant
    end

    # List feeds in the system
    # @return [Array<String>] List of feed ids
    def list_feeds(_environment = 'test')
      ret = http_get('feeds')
      ret.map { |f| f['id'] }
    end

    # List resource types. If no feed_id is given all types are listed
    # @param [String] feed_id The id of the feed the type lives under. Can be nil for feedless types
    # @return [Array<ResourceType>] List of types, that can be empty
    def list_resource_types(feed_id = nil)
      if feed_id.nil?
        ret = http_get('/resourceTypes')
      else
        the_feed = hawk_escape_id feed_id
        ret = http_get("/feeds/#{the_feed}/resourceTypes")
      end
      ret.map { |rt| ResourceType.new(rt) }
    end

    # Return all resources for a feed
    # @param [String] feed_id Id of the feed that hosts the resources
    # @param [Boolean] fetch_properties Should the config data be fetched too
    # @return [Array<Resource>] List of resources, which can be empty.
    def list_resources_for_feed(feed_id, fetch_properties = false, filter = {})
      fail 'Feed id must be given' unless feed_id
      the_feed = hawk_escape_id feed_id
      ret = http_get("/feeds/#{the_feed}/resources")
      to_filter = ret.map do |r|
        if fetch_properties
          p = get_config_data_for_resource(r['path'])
          r['properties'] = p['value']
        end
        Resource.new(r)
      end
      filter_entities(to_filter, filter)
    end

    # List the resources for the passed resource type. The representation for
    # resources under a feed are sparse and additional data must be retrieved separately.
    # It is possible though to also obtain runtime properties by setting #fetch_properties to true.
    # @param [String] resource_type_path Canonical path of the resource type. Can be obtained from {ResourceType}.path.
    #   Must not be nil. The tenant_id in the canonical path doesn't have to be there.
    # @param [Boolean] fetch_properties Shall additional runtime properties be fetched?
    # @return [Array<Resource>] List of resources. Can be empty
    def list_resources_for_type(resource_type_path, fetch_properties = false)
      path = resource_type_path.is_a?(CanonicalPath) ? resource_type_path : CanonicalPath.parse(resource_type_path)
      resource_type_id = path.resource_type_id
      feed_id = path.feed_id
      if feed_id.nil?
        ret = http_get("resourceTypes/#{resource_type_id}/resources")
      else

        ret = http_get("/feeds/#{feed_id}/resourceTypes/#{resource_type_id}/resources")
      end
      ret.map do |r|
        if fetch_properties && !feed_id.nil?
          p = get_config_data_for_resource(r['path'])
          r['properties'] = p['value']
        end
        Resource.new(r)
      end
    end

    # Retrieve runtime properties for the passed resource
    # @param [String] resource_path Canonical path of the resource to read properties from.
    # @return [Hash<String,Object] Hash with additional data
    def get_config_data_for_resource(resource_path)
      path = resource_path.is_a?(CanonicalPath) ? resource_path : CanonicalPath.parse(resource_path)
      resource_path = path.resource_ids.join('/')
      feed_id = path.feed_id
      query = generate_query_params dataType: 'configuration'
      http_get("feeds/#{feed_id}/resources/#{resource_path}/data#{query}")
    rescue
      {}
    end

    # Obtain the child resources of the passed resource. In case of a WildFly server,
    # those would be Datasources, Deployments and so on.
    # @param [String] parent_res_path Canonical path of the resource to obtain children from.
    # @param [Boolean] recursive Whether to fetch also all the children of children of ...
    # @return [Array<Resource>] List of resources that are children of the given parent resource.
    #   Can be empty
    def list_child_resources(parent_res_path, recursive = false)
      path = parent_res_path.is_a?(CanonicalPath) ? parent_res_path : CanonicalPath.parse(parent_res_path)
      parent_resource_path = path.resource_ids.join('/')
      feed_id = path.feed_id
      which_children = (recursive ? '/recursiveChildren' : '/children')
      ret = http_get("/feeds/#{feed_id}/resources/#{parent_resource_path}#{which_children}")
      ret.map { |r| Resource.new(r) }
    end

    # Obtain a list of relationships starting at the passed resource
    # @param [String] entity_path Canonical path of the entity that forms the one end of the relationship
    # @param [String] named Name of the relationship
    # @return [Array<Relationship>] List of relationships
    def list_relationships(entity_path, named = nil)
      path = entity_path.is_a?(CanonicalPath) ? entity_path : CanonicalPath.parse(entity_path)
      query_params = {
        sort: '__targetCp'
      }
      query_params[:named] = named unless named.nil?
      query = generate_query_params query_params
      ret = http_get("/path#{path}/relationships#{query}")
      ret.map { |r| Relationship.new(r) }
    end

    # Obtain a list of relationships for the passed feed
    # @param [String] feed_id Id of the feed
    # @param [String] named Name of the relationship
    # @return [Array<Relationship>] List of relationships
    def list_relationships_for_feed(feed_id, named = nil)
      the_feed = hawk_escape_id feed_id
      query_params = {
        sort: '__targetCp'
      }
      query_params[:named] = named unless named.nil?
      query = generate_query_params query_params
      ret = http_get("/feeds/#{the_feed}/relationships#{query}")
      ret.map { |r| Relationship.new(r) }
    rescue
      []
    end

    # Retrieve a single entity from inventory by its canonical path
    # @param [String] path canonical path of the entity
    # @return inventory entity
    def get_entity(path)
      c_path = path.is_a?(CanonicalPath) ? path : CanonicalPath.parse(path)
      http_get("path#{c_path}")
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

    # List the metrics for the passed metric type. If feed is not passed in the path,
    # all the metrics across all the feeds of a given type will be retrieved
    # This method may perform multiple REST calls.
    # @param [String] metric_type_path Canonical path of the resource type to look for. Can be obtained from
    #   {MetricType}.path. Must not be nil. The tenant_id in the canonical path doesn't have to be there.
    # @return [Array<Metric>] List of metrics. Can be empty
    def list_metrics_for_metric_type(metric_type_path)
      path = metric_type_path.is_a?(CanonicalPath) ? metric_type_path : CanonicalPath.parse(metric_type_path)
      metric_type_id = path.metric_type_id
      feed_id = path.feed_id
      if feed_id.nil?
        type_hash = http_get("metricTypes/#{metric_type_id}")
      else
        type_hash = http_get("/feeds/#{feed_id}/metricTypes/#{metric_type_id}")
      end

      relations = list_relationships(type_hash['path'], 'defines')
      relations.map do |rel|
        metric_hash = get_entity rel.target_id.to_s
        Metric.new(metric_hash)
      end
    rescue
      []
    end

    # List the metrics for all the resources of a given resource type.
    # If feed is not passed in the resource type canonical path, all the metrics across all the feeds of a resource
    # type will be retrieved. This method may perform multiple REST calls.
    # @param [String] resource_type_path Canonical path of the resource type to look for. Can be obtained from
    #   {ResourceType}.path. Must not be nil. The tenant_id in the canonical path doesn't have to be there.
    # @return [Array<Metric>] List of metrics. Can be empty
    def list_metrics_for_resource_type(resource_type_path)
      path = resource_type_path.is_a?(CanonicalPath) ? resource_type_path : CanonicalPath.parse(resource_type_path)
      resource_type_id = path.resource_type_id
      feed_id = path.feed_id

      if feed_id.nil?
        ret = http_get("resourceTypes/#{resource_type_id}/resources")
      else
        ret = http_get("feeds/#{feed_id}/resourceTypes/#{resource_type_id}/resources")
      end
      ret.flat_map do |r|
        path = CanonicalPath.parse(r['path'])
        query = generate_query_params sort: 'id'
        if !path.feed_id.nil?
          nested_ret = http_get("feeds/#{path.feed_id}/resources/#{path.resource_ids.join('/')}/metrics#{query}")
        else
          nested_ret = http_get("#{path.environment_id}/resources/#{path.resource_ids.join('/')}/metrics#{query}")
        end
        nested_ret.map { |m| Metric.new(m) }
      end
    end

    # List metric (definitions) for the passed resource. It is possible to filter down the
    #   result by a filter to only return a subset. The
    # @param [String] resource_path Canonical path of the resource.
    # @param [Hash{Symbol=>String}] filter for 'type' and 'match'
    #   Metric type can be one of 'GAUGE', 'COUNTER', 'AVAILABILITY'. If a key is missing
    #   it will not be used for filtering
    # @return [Array<Metric>] List of metrics that can be empty.
    # @example
    #    # Filter by type and match on metrics id
    #    client.list_metrics_for_resource(wild_fly, type: 'GAUGE', match: 'Metrics~Heap')
    #    # Filter by type only
    #    client.list_metrics_for_resource(wild_fly, type: 'COUNTER')
    #    # Don't filter, return all metric definitions
    #    client.list_metrics_for_resource(wild_fly)
    def list_metrics_for_resource(resource_path, filter = {})
      path = resource_path.is_a?(CanonicalPath) ? resource_path : CanonicalPath.parse(resource_path)
      feed_id = path.feed_id
      resource_path_escaped = path.resource_ids.join('/')

      query = generate_query_params sort: 'id'
      ret = http_get("/feeds/#{feed_id}/resources/#{resource_path_escaped}/metrics#{query}")
      to_filter = ret.map { |m| Metric.new(m) }
      filter_entities(to_filter, filter)
    end

    # Create a new feed
    # @param [String] feed_id  Id of a feed - required
    # @param [String] feed_name A display name for the feed
    # @return [Object]
    def create_feed(feed_id, feed_name = nil)
      feed = create_blueprint
      feed[:id] = feed_id
      feed[:name] = feed_name

      begin
        return http_post('/feeds/', feed)
      rescue HawkularException  => error
        # 409 We already exist -> that is ok
        if error.status_code == 409
          the_feed = hawk_escape_id feed_id
          http_get("/feeds/#{the_feed}")
        else
          raise
        end
      end
    end

    # Delete the feed with the passed feed id.
    # @param feed_id Id of the feed to be deleted.
    def delete_feed(feed_id)
      the_feed = hawk_escape_id feed_id
      http_delete("/feeds/#{the_feed}")
    end

    # Create a new resource type
    # @param [String] feed_id Id of the feed to add the type to
    # @param [String] type_id Id of the new type
    # @param [String] type_name Name of the type
    # @return [ResourceType] ResourceType object just created
    def create_resource_type(feed_id, type_id, type_name)
      the_feed = hawk_escape_id feed_id

      type = create_blueprint
      type[:id] = type_id
      type[:name] = type_name

      begin
        http_post("/feeds/#{the_feed}/resourceTypes", type)
      rescue HawkularException => error
        # 409 We already exist -> that is ok
        raise unless error.status_code == 409
      ensure
        the_type = hawk_escape_id type_id
        res = http_get("/feeds/#{the_feed}/resourceTypes/#{the_type}")
      end
      ResourceType.new(res)
    end

    # Create a resource of a given type. To retrieve that resource
    # you need to call {#get_resource}
    # @param [String] resource_type_path Canonical path of the new resource's type.
    # @param [String] resource_id Id of the new resource
    # @param [String] resource_name Name of the new resource
    # @param [Hash<String,Object>] properties Additional properties. Those are not the config-properties
    def create_resource(resource_type_path, resource_id, resource_name = nil, properties = {})
      create_resource_under_resource(resource_type_path, nil, resource_id, resource_name, properties)
    end

    # Create a resource of a given type under a given resource. To retrieve that resource
    # you need to call {#get_resource}
    # @param [String] res_type_path Canonical path of the new resource's type.
    # @param [String] parent_res_path Canonical path of the resource under which we create this resource.
    #   If nil, the top-lvl resource will be created.
    # @param [String] resource_id Id of the resource
    # @param [String] resource_name Name of the resource
    # @param [Hash<String,Object>] properties Additional properties. Those are not the config-properties
    def create_resource_under_resource(res_type_path, parent_res_path, resource_id, resource_name = nil,
                                       properties = {})
      type_path = res_type_path.is_a?(CanonicalPath) ? res_type_path : CanonicalPath.parse(res_type_path)
      feed_id = type_path.feed_id

      res = create_blueprint
      res[:properties] = properties
      res[:id] = resource_id
      res[:name] = resource_name
      res[:resourceTypePath] = type_path.to_s

      begin
        if parent_res_path.nil?
          res = http_post("/feeds/#{feed_id}/resources", res)
        else
          path = parent_res_path.is_a?(CanonicalPath) ? parent_res_path : CanonicalPath.parse(parent_res_path)
          resource_path = path.resource_ids.join('/')
          res = http_post("/feeds/#{feed_id}/resources/#{resource_path}", res)
        end
      rescue HawkularException => error
        # 409 We already exist -> that is ok
        raise unless error.status_code == 409
      end
      Resource.new(res)
    end

    # Return the resource object for the passed path
    # @param [String] resource_path Canonical path of the resource to fetch.
    # @param [Boolean] fetch_resource_config Should the resource config data be fetched?
    def get_resource(resource_path, fetch_resource_config = true)
      path = resource_path.is_a?(CanonicalPath) ? resource_path : CanonicalPath.parse(resource_path)
      feed_id = path.feed_id
      res_path = path.resource_ids.join('/')

      res = http_get("/feeds/#{feed_id}/resources/#{res_path}")
      if fetch_resource_config
        p = get_config_data_for_resource(resource_path)
        res['properties'] ||= {}
        res['properties'].merge p['value'] unless p['value'].nil?
      end
      Resource.new(res)
    end

    # Create a new metric type for a feed
    # @param [String] feed_id Id of the feed
    # @param [String] metric_type_id Id of the metric type to create
    # @param [String] type Type of the Metric. Allowed are GAUGE,COUNTER, AVAILABILITY
    # @param [String] unit Unit of the metric
    # @param [Numeric] collection_interval
    # @return [MetricType] Type just created or the one from the server if it already existed.
    def create_metric_type(feed_id, metric_type_id, type = 'GAUGE', unit = 'NONE', collection_interval = 60)
      the_feed = hawk_escape_id feed_id

      metric_kind = type.nil? ? 'GAUGE' : type.upcase
      fail "Unknown type #{metric_kind}" unless %w(GAUGE COUNTER AVAILABILITY').include?(metric_kind)

      mt = build_metric_type_hash(collection_interval, metric_kind, metric_type_id, unit)

      begin
        http_post("/feeds/#{the_feed}/metricTypes", mt)
      rescue HawkularException => error
        # 409 We already exist -> that is ok
        raise unless error.status_code == 409
      end

      new_mt = http_get("/feeds/#{the_feed}/metricTypes/#{metric_type_id}")

      MetricType.new(new_mt)
    end

    # List operation definitions (types) for a given resource type
    # @param [String] resource_type_path canonical path of the resource type entity
    # @return [Array<String>] List of operation type ids
    def list_operation_definitions(resource_type_path)
      parsed_path = CanonicalPath.parse(resource_type_path.to_s)
      feed_id = parsed_path.feed_id
      resource_type_id = parsed_path.resource_type_id
      ret = http_get("/feeds/#{feed_id}/resourceTypes/#{resource_type_id}/operationTypes")
      ret.map { |ot| ot['id'] }
    end

    # List operation definitions (types) for a given resource
    # @param [String] resource_path canonical path of the resource entity
    # @return [Array<String>] List of operation type ids
    def list_operation_definitions_for_resource(resource_path)
      resource = get_resource(resource_path.to_s, false)
      list_operation_definitions(resource.type_path)
    end

    # Create a Metric and associate it with a resource.
    # @param [String] metric_type_path Canonical path of the metric type of the new metric.
    # @param [String] resource_path Canonical path of the resource to which we want to associate the metric.
    # @param [String] metric_id Id of the metric
    # @param [String] metric_name a (display) name for the metric. If nil, #metric_id is used.
    # @return [Metric] The metric created or if it already existed the version from the server
    def create_metric_for_resource(metric_type_path, resource_path, metric_id, metric_name = nil)
      type_path = metric_type_path.is_a?(CanonicalPath) ? metric_type_path : CanonicalPath.parse(metric_type_path)
      feed_id = type_path.feed_id
      res_path = resource_path.is_a?(CanonicalPath) ? resource_path : CanonicalPath.parse(resource_path)
      res_path_str = res_path.resource_ids.join('/')

      m = {}
      m['id'] = metric_id
      m['name'] = metric_name || metric_id
      m['metricTypePath'] = type_path.to_s

      begin
        http_post("/feeds/#{feed_id}/metrics", m)
      rescue HawkularException => error
        # 409 We already exist -> that is ok
        raise unless error.status_code == 409
      end

      ret = http_get("/feeds/#{feed_id}/metrics/#{metric_id}")
      the_metric = Metric.new(ret)

      begin
        http_post("/feeds/#{feed_id}/resources/#{res_path_str}/metrics", [the_metric.path])
      rescue HawkularException => error
        # 409 We already exist -> that is ok
        raise unless error.status_code == 409
      end
      the_metric
    end

    # Listen on inventory changes
    # @param [String] type Type of entity for which we want the events.
    # Allowed values: resource, metric, resourcetype, metrictype, feed, environment, operationtype, metadatapack
    # @param [String] action What types of events are we interested in.
    # Allowed values: created, updated, deleted, copied, registered
    def events(type = 'resource', action = 'created')
      tenant_id = get_tenant
      url = "#{entrypoint.gsub(/https?/, 'ws')}/ws/events?tenantId=#{tenant_id}&type=#{type}&action=#{action}"
      @ws = WebSocket::Client::Simple.connect url do |client|
        client.on :message do |msg|
          parsed_message = JSON.parse(msg.data)
          entity = case type
                   when 'resource'
                     Resource.new(parsed_message)
                   when 'resourcetype'
                     ResourceType.new(parsed_message)
                   when 'metric'
                     Metric.new(parsed_message)
                   when 'metrictype'
                     MetricType.new(parsed_message)
                   else
                     BaseEntity.new(parsed_message)
                   end
          yield entity
        end
      end
    end

    # Stop listening on inventory events.
    # this method closes the web socket connection
    def no_more_events!
      @ws.close
    end

    def to_s
      'inventory'
    end

    private

    # Creates a hash with the fields required by the Blueprint api in Hawkular-Inventory
    def create_blueprint
      res = {}
      res[:properties] = {}
      res[:id] = nil
      res[:name] = nil
      res[:outgoing] = {}
      res[:incoming] = {}
      res
    end

    def build_metric_type_hash(collection_interval, metric_kind, metric_type_id, unit)
      mt = {}
      mt['id'] = metric_type_id
      mt['type'] = metric_kind
      mt['unit'] = unit.nil? ? 'NONE' : unit.upcase
      mt['collectionInterval'] = collection_interval.nil? ? 60 : collection_interval
      mt
    end

    def filter_entities(entities, filter)
      entities.select do |entity|
        found = true
        if filter.empty?
          found = true
        else
          found = false unless filter[:type] == (entity.type) || filter[:type].nil?
          found = false unless filter[:match].nil? || entity.id.include?(filter[:match])
        end
        found
      end
    end
  end

  # A Basic inventory entity with id, name, path and optional properties
  class BaseEntity
    # @return [String] Full path of the entity
    attr_reader :path
    # @return [String] Name of the entity
    attr_reader :name
    # @return [String] Name of the entity
    attr_reader :id
    # @return [String] Feed this entity belongs to (or nil in case of a feedless entity)
    attr_reader :feed
    # @return [String] Name of the environment for this entity
    attr_reader :env
    # @return [String] Properties of this entity
    attr_reader :properties

    def initialize(hash)
      @id = hash['id']
      @path = hash['path']
      @name = hash['name'] || @id
      @properties = hash['properties'] || {}
      @_hash = hash.dup

      return if @path.nil?

      tmp = @path.split('/')
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

    def ==(other)
      self.eql?(other) || other.class == self.class && other.id == @id
    end

    # Returns a hash representation of the resource type
    # @return [Hash<String,Object>] hash of the type
    def to_h
      @_hash.dup
    end
  end

  # A ResourceType is like a class definition for {Resource}s
  # ResourceTypes are currently unique per feed, but one can assume
  # that a two types with the same name of two different feeds are
  # (more or less) the same.
  class ResourceType < BaseEntity
    def initialize(rt_hash)
      super(rt_hash)
    end
  end

  # A Resource is an instantiation of a {ResourceType}
  class Resource < BaseEntity
    # @return [String] Full path of the {ResourceType}
    attr_reader :type_path

    def initialize(res_hash)
      super(res_hash)
      @type = res_hash['type']
      @type_path = res_hash['type']['path']
    end
  end

  class MetricType < BaseEntity
    # @return [String] GAUGE, COUNTER, etc.
    attr_reader :type
    # @return [String] metric unit such as NONE, BYTES, etc.
    attr_reader :unit
    # @return [Long] collection interval in seconds
    attr_reader :collection_interval

    def initialize(type_hash)
      super(type_hash)
      @type = type_hash['type']
      @unit = type_hash['unit']
      @collection_interval = type_hash['collectionInterval']
    end
  end

  # Definition of a Metric inside the inventory.
  class Metric < BaseEntity
    # @return [String] GAUGE, COUNTER, etc.
    attr_reader :type
    # @return [String] metric unit such as NONE, BYTES, etc.
    attr_reader :unit
    # @return [Long] collection interval in seconds
    attr_reader :collection_interval

    def initialize(metric_hash)
      super(metric_hash)
      @type = metric_hash['type']['type']
      @type_path = metric_hash['type']['path']
      @unit = metric_hash['type']['unit']
      @collection_interval = metric_hash['type']['collectionInterval']
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

  class CanonicalPath
    attr_reader :tenant_id
    attr_reader :feed_id
    attr_reader :environment_id
    attr_reader :resource_ids
    attr_reader :metric_id
    attr_reader :resource_type_id
    attr_reader :metric_type_id

    def initialize(hash)
      @tenant_id = hash[:tenant_id]
      @feed_id = hash[:feed_id]
      @environment_id = hash[:environment_id]
      @resource_type_id = hash[:resource_type_id]
      @metric_type_id = hash[:metric_type_id]
      @resource_ids = hash[:resource_ids]
      @metric_id = hash[:metric_id]
    end

    # rubocop:disable Metrics/CyclomaticComplexity
    def self.parse(path)
      fail 'CanonicalPath must not be nil or emtpy' if path.to_s.strip.length == 0
      tmp = path.split('/')
      hash = {}
      tmp.each do |pair|
        (key, val) = pair.split(';')
        case key
        when 't'
          hash[:tenant_id] = val
        when 'f'
          hash[:feed_id] = val
        when 'e'
          hash[:environment_id] = val
        when 'm'
          hash[:metric_id] = val
        when 'r'
          hash[:resource_ids] = [] if hash[:resource_ids].nil?
          hash[:resource_ids].push(val)
        when 'mt'
          hash[:metric_type_id] = val
        when 'rt'
          hash[:resource_type_id] = val
        end
      end
      CanonicalPath.new(hash)
    end
    # rubocop:enable Metrics/CyclomaticComplexity

    def ==(other)
      self.eql?(other) || other.class == self.class && other.state == state
    end

    def to_s
      ret = "/t;#{@tenant_id}"
      ret += "/f;#{@feed_id}" unless @feed_id.nil?
      ret += "/e;#{@environment_id}" unless @environment_id.nil?
      ret += "/rt;#{@resource_type_id}" unless @resource_type_id.nil?
      ret += "/mt;#{@metric_type_id}" unless @metric_type_id.nil?
      ret += "/m;#{@metric_id}" unless @metric_id.nil?
      ret += resources_chunk.to_s
      ret
    end

    protected

    def state
      [@tenant_id, @feed_id, @environment_id, @resource_ids, @metric_id, @metric_type_id, @resource_type_id]
    end

    private

    def resources_chunk
      @resource_ids.map { |r| "/r;#{r}" }.join unless @resource_ids.nil?
    end
  end
end
