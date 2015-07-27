require 'hawkularclient'
require 'rspec/core'
require 'rspec/mocks'
require 'socket'
require 'uri'
require 'yaml'

module Hawkular::Metrics::RSpec

  def setup_client(options = {})
    user, password, url = config['user'], config['password'], config['url']
    @client = Hawkular::Metrics::Client.new(url, user, password, options)
  end

  def setup_client_new_tenant(options = {})
	setup_client
    @tenant = SecureRandom.uuid
    @client.tenants.create(@tenant)
    setup_client({:tenant => @tenant})
  end

  def config
    @config ||= YAML.load(File.read(File.expand_path("endpoint.yml", File.dirname(__FILE__))))
  end

end

RSpec.configure do |config|
  config.include Hawkular::Metrics::RSpec
end
