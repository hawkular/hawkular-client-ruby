require 'hawkular/base_client'
require 'hawkular/websocket_client'
require 'json'
require 'zlib'
require 'stringio'

require 'hawkular/inventory/entities'

# Inventory module provides access to the Hawkular Inventory REST API.
# @see http://www.hawkular.org/docs/rest/rest-inventory.html
#
# @note While Inventory supports 'environments', they are not used currently
#   and thus set to 'test' as default value.
module Hawkular::Inventory
  # Client class to interact with Hawkular Inventory
  class Client < Hawkular::BaseClient
    attr_reader :version

    # Create a new Inventory Client
    # @param entrypoint [String] base url of Hawkular-inventory - e.g
    #   http://localhost:8080/hawkular/inventory
    # @param credentials [Hash{String=>String}] Hash of username, password, token(optional)
    # @param options [Hash{String=>String}] Additional rest client options
    def initialize(entrypoint = nil, credentials = {}, options = {})
      entrypoint = normalize_entrypoint_url entrypoint, 'hawkular/metrics'
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
      fail 'no parameter ":entrypoint" given' unless hash[:entrypoint]
      hash[:credentials] ||= {}
      hash[:options] ||= {}
      Client.new(hash[:entrypoint], hash[:credentials], hash[:options])
    end

    # List feeds in the system
    # @return [Array<String>] List of feed ids
    def list_feeds
      ret = http_get('/strings/tags/module:inventory,feed:*')
      return [] unless ret.key? 'feed'
      ret['feed']
    end

    # List resource types for the given feed
    # @param [String] feed_id The id of the feed the type lives under
    # @return [Array<ResourceType>] List of types, that can be empty
    def list_resource_types(feed_id)
      fail 'Feed id must be given' unless feed_id
      feed_path = feed_cp(feed_id)
      response = http_post(
        '/strings/raw/query',
        fromEarliest: true,
        order: 'DESC',
        tags: "#{feed_path.to_tags},type:rt")
      structures = extract_structures_from_body(response)
      structures.map do |rt|
        root_hash = entity_json_to_hash(-> (id) { feed_path.resource_type(id) }, rt['inventoryStructure'], false)
        ResourceType.new(root_hash)
      end
    end

    # List metric types for the given feed
    # @param [String] feed_id The id of the feed the type lives under
    # @return [Array<MetricType>] List of types, that can be empty
    def list_metric_types(feed_id)
      fail 'Feed id must be given' unless feed_id
      feed_path = feed_cp(feed_id)
      response = http_post(
        '/strings/raw/query',
        fromEarliest: true,
        order: 'DESC',
        tags: "#{feed_path.to_tags},type:mt")
      structures = extract_structures_from_body(response)
      structures.map do |mt|
        root_hash = entity_json_to_hash(-> (id) { feed_path.metric_type(id) }, mt['inventoryStructure'], false)
        MetricType.new(root_hash)
      end
    end

    # Return all resources for a feed
    # @param [String] feed_id Id of the feed that hosts the resources
    # @param [Boolean] fetch_properties Should the config data be fetched too
    # @return [Array<Resource>] List of resources, which can be empty.
    def list_resources_for_feed(feed_id, fetch_properties = false, filter = {})
      fail 'Feed id must be given' unless feed_id
      feed_path = feed_cp(feed_id)
      response = http_post(
        '/strings/raw/query',
        fromEarliest: true,
        order: 'DESC',
        tags: "#{feed_path.to_tags},type:r")
      structures = extract_structures_from_body(response)
      to_filter = structures.map do |r|
        root_hash = entity_json_to_hash(-> (id) { feed_path.down(id) }, r['inventoryStructure'], fetch_properties)
        Resource.new(root_hash)
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
      path = CanonicalPath.parse_if_string(resource_type_path)
      fail 'Feed id must be given' unless path.feed_id
      fail 'Resource type must be given' unless path.resource_type_id

      # Fetch metrics by tag
      feed_path = feed_cp(URI.unescape(path.feed_id))
      resource_type_id = URI.unescape(path.resource_type_id)
      escaped_for_regex = Regexp.quote("|#{resource_type_id}|")
      response = http_post(
        '/strings/raw/query',
        fromEarliest: true,
        order: 'DESC',
        tags: "#{feed_path.to_tags},type:r,restypes:.*#{escaped_for_regex}.*")
      structures = extract_structures_from_body(response)
      return [] if structures.empty?

      # Now find each collected resource path in their belonging InventoryStructure
      extract_resources_for_type(structures, feed_path, resource_type_id, fetch_properties)
    end

    # Retrieve runtime properties for the passed resource
    # @param [String] resource_path Canonical path of the resource to read properties from.
    # @return [Hash<String,Object] Hash with additional data
    def get_config_data_for_resource(resource_path)
      path = CanonicalPath.parse_if_string(resource_path)
      raw_hash = get_raw_entity_hash(path)
      return {} unless raw_hash
      { 'value' => fetch_properties(raw_hash) }
    end

    # Obtain the child resources of the passed resource. In case of a WildFly server,
    # those would be Datasources, Deployments and so on.
    # @param [String] parent_res_path Canonical path of the resource to obtain children from.
    # @param [Boolean] recursive Whether to fetch also all the children of children of ...
    # @return [Array<Resource>] List of resources that are children of the given parent resource.
    #   Can be empty
    def list_child_resources(parent_res_path, recursive = false)
      path = CanonicalPath.parse_if_string(parent_res_path)
      feed_id = path.feed_id
      fail 'Feed id must be given' unless feed_id
      entity_hash = get_raw_entity_hash(path)
      extract_child_resources([], path.to_s, entity_hash, recursive) if entity_hash
    end

    # List the metrics for the passed metric type. If feed is not passed in the path,
    # all the metrics across all the feeds of a given type will be retrieved
    # @param [String] metric_type_path Canonical path of the resource type to look for. Can be obtained from
    #   {MetricType}.path. Must not be nil. The tenant_id in the canonical path doesn't have to be there.
    # @return [Array<Metric>] List of metrics. Can be empty
    def list_metrics_for_metric_type(metric_type_path)
      path = CanonicalPath.parse_if_string(metric_type_path)
      fail 'Feed id must be given' unless path.feed_id
      fail 'Metric type id must be given' unless path.metric_type_id
      feed_id = URI.unescape(path.feed_id)
      metric_type_id = URI.unescape(path.metric_type_id)

      feed_path = feed_cp(feed_id)
      escaped_for_regex = Regexp.quote("|#{metric_type_id}|")
      response = http_post(
        '/strings/raw/query',
        fromEarliest: true,
        order: 'DESC',
        tags: "#{feed_path.to_tags},type:r,mtypes:.*#{escaped_for_regex}.*")
      structures = extract_structures_from_body(response)
      return [] if structures.empty?

      # Now find each collected resource path in their belonging InventoryStructure
      metric_type = get_metric_type(path)
      extract_metrics_for_type(structures, feed_path, metric_type)
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
      path = CanonicalPath.parse_if_string(resource_path)
      raw_hash = get_raw_entity_hash(path)
      return [] unless raw_hash
      to_filter = []
      if (raw_hash.key? 'children') && (raw_hash['children'].key? 'metric') && !raw_hash['children']['metric'].empty?
        # Need to merge metric type info that we must grab from another place
        metric_types = list_metric_types(path.feed_id)
        metric_types_index = {}
        metric_types.each { |mt| metric_types_index[mt.path] = mt }
        to_filter = raw_hash['children']['metric'].map do |m|
          metric_data = m['data']
          metric_data['path'] = "#{path}/m;#{metric_data['id']}"
          metric_type = metric_types_index[metric_data['metricTypePath']]
          Metric.new(metric_data, metric_type) if metric_type
        end
        to_filter = to_filter.select { |m| m }
      end
      filter_entities(to_filter, filter)
    end

    # Return the resource object for the passed path
    # @param [String] resource_path Canonical path of the resource to fetch.
    # @param [Boolean] fetch_properties Should the resource config data be fetched?
    def get_resource(resource_path, fetch_properties = true)
      path = CanonicalPath.parse_if_string(resource_path)
      raw_hash = get_raw_entity_hash(path)
      unless raw_hash
        exception = HawkularException.new("Resource not found: #{resource_path}")
        fail exception
      end
      entity_hash = entity_json_to_hash(-> (_) { path }, raw_hash, fetch_properties)
      Resource.new(entity_hash)
    end

    # Return the resource type object for the passed path
    # @param [String] resource_type_path Canonical path of the resource type to fetch.
    def get_resource_type(resource_type_path)
      path = CanonicalPath.parse_if_string(resource_type_path)
      raw_hash = get_raw_entity_hash(path)
      unless raw_hash
        exception = HawkularException.new("Resource type not found: #{resource_type_path}")
        fail exception
      end
      entity_hash = entity_json_to_hash(-> (_) { path }, raw_hash, false)
      ResourceType.new(entity_hash)
    end

    # Return the metric type object for the passed path
    # @param [String] metric_type_path Canonical path of the metric type to fetch.
    def get_metric_type(metric_type_path)
      path = CanonicalPath.parse_if_string(metric_type_path)
      raw_hash = get_raw_entity_hash(path)
      unless raw_hash
        exception = HawkularException.new("Metric type not found: #{metric_type_path}")
        fail exception
      end
      entity_hash = entity_json_to_hash(-> (_) { path }, raw_hash, false)
      MetricType.new(entity_hash)
    end

    # List operation definitions (types) for a given resource type
    # @param [String] resource_type_path canonical path of the resource type entity
    # @return [Array<String>] List of operation type ids
    def list_operation_definitions(resource_type_path)
      path = CanonicalPath.parse_if_string(resource_type_path)
      fail 'Missing feed_id in resource_type_path' unless path.feed_id
      fail 'Missing resource_type_id in resource_type_path' unless path.resource_type_id
      response = http_post(
        '/strings/raw/query',
        fromEarliest: true,
        order: 'DESC',
        tags: path.to_tags)
      structures = extract_structures_from_body(response)
      res = {}
      structures.map { |rt| rt['inventoryStructure'] }
        .select { |rt| rt['children'] && rt['children']['operationType'] }
        .flat_map { |rt| rt['children']['operationType'] }
        .each do |ot|
        hash = optype_json_to_hash(ot)
        od = OperationDefinition.new hash
        res[od.name] = od
      end
      res
    end

    # List operation definitions (types) for a given resource
    # @param [String] resource_path canonical path of the resource entity
    # @return [Array<String>] List of operation type ids
    def list_operation_definitions_for_resource(resource_path)
      resource = get_resource(resource_path, false)
      list_operation_definitions(resource.type_path)
    end

    # Return version and status information for the used version of Hawkular-Inventory
    # @return [Hash{String=>String}]
    #         ('Implementation-Version', 'Built-From-Git-SHA1', 'Status')
    def fetch_version_and_status
      http_get('/status')
    end

    def feed_cp(feed_id)
      CanonicalPath.new(tenant_id: @tenant, feed_id: hawk_escape_id(feed_id))
    end

    private

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

    def entity_json_to_hash(path_getter, json, fetch_properties)
      data = json['data']
      data['path'] = path_getter.call(data['id']).to_s
      if fetch_properties
        props = fetch_properties(json)
        data['properties'].merge! props if props
      end
      data
    end

    def fetch_properties(json)
      return unless (json.key? 'children') && (json['children'].key? 'dataEntity')
      config = json['children']['dataEntity'].find { |d| d['data']['id'] == 'configuration' }
      config['data']['value'] if config
    end

    def optype_json_to_hash(json)
      data = json['data']
      # Fetch parameterTypes
      if (json.key? 'children') && (json['children'].key? 'dataEntity')
        param_types = json['children']['dataEntity'].find { |d| d['data']['id'] == 'parameterTypes' }
        data['parameters'] = param_types['data']['value'] if param_types
      end
      data
    end

    def get_raw_entity_hash(path)
      c_path = CanonicalPath.parse_if_string(path)
      raw = http_post(
        '/strings/raw/query',
        fromEarliest: true,
        order: 'DESC',
        tags: c_path.to_tags
      )
      structure = extract_structure_from_body(raw)
      find_entity_in_tree(c_path, structure)
    end

    def find_entity_in_tree(fullpath, inventory_structure)
      entity = inventory_structure
      if fullpath.resource_ids
        relative = fullpath.resource_ids.drop(1)
        relative.each do |child|
          if (entity.key? 'children') && (entity['children'].key? 'resource')
            unescaped = URI.unescape(child)
            entity = entity['children']['resource'].find { |r| r['data']['id'] == unescaped }
          else
            entity = nil
            break
          end
        end
      end
      if fullpath.metric_id
        if (entity.key? 'children') && (entity['children'].key? 'metric')
          unescaped = URI.unescape(fullpath.metric_id)
          entity = entity['children']['metric'].find { |r| r['data']['id'] == unescaped }
        else
          entity = nil
        end
      end
      entity
    end

    def extract_child_resources(arr, path, parent_hash, recursive)
      c_path = CanonicalPath.parse_if_string(path)
      if (parent_hash.key? 'children') && (parent_hash['children'].key? 'resource')
        parent_hash['children']['resource'].each do |r|
          entity = entity_json_to_hash(-> (id) { c_path.down(id) }, r, false)
          arr.push(Resource.new(entity))
          extract_child_resources(arr, entity['path'], r, true) if recursive
        end
      end
      arr
    end

    def extract_resources_for_type(structures, feed_path, resource_type_id, fetch_properties)
      matching_resources = []
      structures.each do |full_struct|
        next unless full_struct.key? 'typesIndex'
        next unless full_struct['typesIndex'].key? resource_type_id
        inventory_structure = full_struct['inventoryStructure']
        root_path = feed_path.down(inventory_structure['data']['id'])
        full_struct['typesIndex'][resource_type_id].each do |relative_path|
          if relative_path.empty?
            # Root resource
            resource = entity_json_to_hash(-> (id) { feed_path.down(id) }, inventory_structure, fetch_properties)
            matching_resources.push(Resource.new(resource))
          else
            # Search for child
            fullpath = CanonicalPath.parse("#{root_path}/#{relative_path}")
            resource_json = find_entity_in_tree(fullpath, inventory_structure)
            if resource_json
              resource = entity_json_to_hash(-> (_) { fullpath }, resource_json, fetch_properties)
              matching_resources.push(Resource.new(resource))
            end
          end
        end
      end
      matching_resources
    end

    def extract_metrics_for_type(structures, feed_path, metric_type)
      matching_metrics = []
      structures.each do |full_struct|
        next unless full_struct.key? 'metricTypesIndex'
        next unless full_struct['metricTypesIndex'].key? metric_type.id
        inventory_structure = full_struct['inventoryStructure']
        root_path = feed_path.down(inventory_structure['data']['id'])
        full_struct['metricTypesIndex'][metric_type.id].each do |relative_path|
          # Search for child
          fullpath = CanonicalPath.parse("#{root_path}/#{relative_path}")
          metric_json = find_entity_in_tree(fullpath, inventory_structure)
          if metric_json
            metric_hash = entity_json_to_hash(-> (_) { fullpath }, metric_json, false)
            matching_metrics.push(Metric.new(metric_hash, metric_type))
          end
        end
      end
      matching_metrics
    end

    def extract_structure_from_body(response_body_array)
      # Expecting only 1 structure (but may have several chunks)
      structures = extract_structures_from_body(response_body_array)
      structures[0]['inventoryStructure'] unless structures.empty?
    end

    def extract_structures_from_body(response_body_array)
      response_body_array.map { |element| rebuild_from_chunks(element['data']) }
        .select { |full| full } # evict nil
        .map { |full| decompress(full) }
    end

    def rebuild_from_chunks(data_node)
      return if data_node.empty?
      master_data = data_node[0]
      return Base64.decode64(master_data['value']) unless (master_data.key? 'tags') &&
                                                          (master_data['tags'].key? 'chunks')
      last_chunk = master_data['tags']['chunks'].to_i - 1
      all = Base64.decode64(master_data['value'])
      return if all.empty?
      (1..last_chunk).inject(all) do |full, chunk_id|
        slave_data = data_node[chunk_id]
        full.concat(Base64.decode64(slave_data['value']))
      end
    end

    def decompress(raw)
      gz = Zlib::GzipReader.new(StringIO.new(raw))
      JSON.parse(gz.read)
    end
  end

  InventoryClient = Client
  deprecate_constant :InventoryClient if self.respond_to? :deprecate_constant
end
