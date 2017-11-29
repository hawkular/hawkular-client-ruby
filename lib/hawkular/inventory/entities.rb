# It contains class definitions that are used by the inventory REST client
module Hawkular::Inventory
  class Metric
    # @return [String] Provider Name of the metric
    attr_reader :name
    # @return [String] Display Name of the metric
    attr_reader :display_name
    # @return [String] Family of the metric (Prometheus family name)
    attr_reader :family
    # @return [String] Promql expression for fetching the  time series
    attr_reader :expression
    # @return [String] Unit of the metric
    attr_reader :unit
    # @return [String] Expression of the metric (Prometheus expression)
    attr_reader :expression
    # @return [Hash<String,String>] Labels of this metric (Prometheus labels)
    attr_reader :labels
    # @return [Hash<String,String>] Properties of this metric
    attr_reader :properties

    def initialize(hash)
      @name = hash['displayName']
      @display_name = hash['displayName']
      @family = hash['family']
      @expression = hash['expression']
      @unit = hash['unit']
      @expression = hash['expression']
      @labels = hash['labels'] || {}
      @properties = hash['properties'] || {}
      @_hash = hash.dup
    end

    # Returns a hash representation of the metric type
    # @return [Hash<String,Object>] hash of the metric type
    def to_h
      @_hash.dup
    end

    def to_h
        metric_hash = {}
        metric_hash['name'] = @name
        metric_hash['displayName'] = @display_name
        metric_hash['family'] = @family
        metric_hash['expression'] = @expression
        metric_hash['unit'] = @unit
        metric_hash['labels'] = @labels
        metric_hash['properties'] = @properties
        metric_hash
      end
  end

  class Operation
    # @return [String] Name of the operation
    attr_reader :name
    attr_reader :params

    def initialize(op_hash)
      @name = op_hash['name']
      @params = (op_hash.key? 'parameters') ? op_hash['parameters'] : {}
    end
  end

  class ResourceType
    # @return [String] Id of the resource type
    attr_reader :id
    # @return [Hash<String,String>] Properties of this resource type
    attr_reader :properties
    # @return [List<Operation>] Operations associated with this type
    attr_reader :operations

    def initialize(hash)
      @id = hash['id']
      @properties = hash['properties'] || {}
      @operations = (hash['operations'] || []).map { |op| Operation.new(op) }
      @_hash = hash.dup
    end

    def ==(other)
      self.equal?(other) || other.class == self.class && other.id == @id
    end

    # Returns a hash representation of the resource type
    # @return [Hash<String,Object>] hash of the resource type
    def to_h
      @_hash.dup
    end
  end

  class Resource
    # @return [String] Id of the entity
    attr_reader :id
    # @return [String] Name of the entity
    attr_reader :name
    # @return [String] Feed this entity belongs to
    attr_reader :feed
    # @return [ResourceType] Type of this resource
    attr_reader :type
    # @return [String] Parent ID of this entity (nil if it's a root resource)
    attr_reader :parent_id
    # @return [Hash<String,String>] Properties of this resource
    attr_reader :properties
    # @return [Hash<String,String>] Config map of this resource
    attr_reader :config
    # @return [List<Metric>] Metrics associated to this resource
    attr_reader :metrics
    # @return [List<Resource>] List of children (present when the whole tree is loaded, else nil)
    attr_reader :children

    def initialize(hash)
      @id = hash['id']
      @name = hash['name']
      @feed = hash['feedId']
      @type = ResourceType.new(hash['type'])
      @parent_id = hash['parentId']
      @properties = hash['properties'] || {}
      @config = hash['config'] || {}
      @metrics = (hash['metrics'] || []).map { |m| Metric.new(m) }
      @children = hash['children'].map { |r| Resource.new(r) } if hash.key? 'children'
      @_hash = hash.dup
    end

    def children(recursive = false)
      return @children unless recursive == true
      fail Hawkular::ArgumentError 'Resource tree not loaded, load it by calling resource_tree' if @children.nil?
      @children.flat_map do |child|
        [child, *child.children(recursive)]
      end
    end

    def children_by_type(type, recursive = false)
      children(recursive).select { |c| c.type.id == type }
    end

    def metrics(recursive = false)
      return @metrics unless recursive == true
      children(recursive).collect(&:metrics).flat_map(&:itself).concat(@metrics)
    end

    def metrics_by_family(family)
      @metrics.select { |m| m.family == family }
    end

    def ==(other)
      self.equal?(other) || other.class == self.class && other.id == @id
    end

    # Returns a hash representation of the resource
    # @return [Hash<String,Object>] hash of the resource
    def to_h
      @_hash.dup
    end
  end
end
