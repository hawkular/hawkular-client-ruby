# It contains class definitions that are used by the inventory REST client
module Hawkular::Inventory
  # A Basic inventory entity with id, name, path and optional properties
  class BaseEntity
    # @return [String] Full path of the entity
    attr_reader :path
    # @return [String] Name of the entity
    attr_reader :name
    # @return [String] Id of the entity
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
      self.equal?(other) || other.class == self.class && other.id == @id
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
      if res_hash.key? :resourceTypePath
        @type_path = res_hash[:resourceTypePath]
      else
        @type = res_hash['type']
        @type_path = res_hash['type']['path']
      end
    end
  end

  # Fields that are common for MetricType and Metric
  module MetricFields
    # @return [String] gauge, counter, etc.
    attr_reader :type
    # @return [String] metric unit such as NONE, BYTES, etc.
    attr_reader :unit
    # @return [Long] collection interval in seconds, it has different semantics for MetricType and for Metric
    #                for MetricType it's a default that will be applied to all the metric of that type,
    #                in the Metric this can be overridden
    attr_reader :collection_interval
  end

  # Definition of a Metric Type inside the inventory.
  class MetricType < BaseEntity
    include MetricFields

    def initialize(type_hash)
      super(type_hash)
      @type = type_hash['metricDataType']
      @unit = type_hash['unit']
      @collection_interval = type_hash['collectionInterval']
    end
  end

  # Definition of a Metric inside the inventory.
  class Metric < BaseEntity
    include MetricFields

    attr_reader :type_id
    # @return [String] metric id used in Hawkular Metrics
    attr_reader :hawkular_metric_id

    def initialize(metric_hash)
      super(metric_hash)
      @type = metric_hash['type']['metricDataType']
      @type_path = metric_hash['type']['path']
      @type_id = metric_hash['type']['id']
      @unit = metric_hash['type']['unit']
      @collection_interval = metric_hash['type']['collectionInterval']
      @hawkular_metric_id = @properties.key?('hawkular-metric-id') ? @properties['hawkular-metric-id'] : @id
    end
  end

  class OperationDefinition < BaseEntity
    attr_reader :params

    def initialize(op_hash)
      super(op_hash)
      @params = (op_hash.key? 'parameters') ? op_hash['parameters'] : {}
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

    def self.parse(path)
      fail 'CanonicalPath must not be nil or empty' if path.to_s.strip.length == 0
      CanonicalPath.new(path_to_h path)
    end

    # Move up to the parent path of the resource. resource_ids set to empty array when there is no parent.
    # @return CanonicalPath corresponding to the direct ancestor of the resource represented by this path object.
    def up
      hash = to_h
      if hash[:resource_ids].nil?
        hash[:resource_ids] = []
      else
        hash[:resource_ids].pop
      end
      CanonicalPath.new(hash)
    end

    def ==(other)
      self.equal?(other) || other.class == self.class && other.state == state
    end

    def to_h
      {
        tenant_id: @tenant_id,
        feed_id: @feed_id,
        environment_id: environment_id,
        resource_type_id: resource_type_id,
        metric_type_id: metric_type_id,
        resource_ids: resource_ids,
        metric_id: @metric_id
      }
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

    def self.path_to_h(path)
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
      hash
    end
  end
end
