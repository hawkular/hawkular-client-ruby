require 'Hawkular'

module Hawkular::Inventory
  class InventoryClient < Hawkular::BaseClient
    def initialize(entrypoint = nil, credentials = {})
      @entrypoint = entrypoint

      super(entrypoint, credentials)
    end

    def get_tenant(credentials = {})
      creds = credentials.empty? ? @credentials : credentials
      auth_header = { Authorization: base_64_credentials(creds) }

      ret = http_get('/tenant', auth_header)

      ret['id']
    end

    # TODO: move to Base ?
    def impersonate(credentials = {})
      @tenant = get_tenant(credentials)
    end

    def list_feeds(environment = 'test')
      ret = http_get('/' + environment + '/feeds')
      val = []
      ret.each { |f| val.push(f['id']) }
      val
    end

    # List resource types. If no need is given all types are listed
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

    def list_resources_for_type(feed, type, environment = 'test')
      if feed.nil?
        puts 'TODO implement me'
        # TODO: we need to find feedless resources
      else
        ret = http_get('/' + environment + '/' + feed + '/resourceTypes/' + type + '/resources')
        val = []
        ret.each { |r| val.push(Resource.new(r['path'], r['id'])) }
        val
      end
    end

    def list_metrics_for_resource_type
    end

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
