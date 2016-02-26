require "#{File.dirname(__FILE__)}/../vcr/vcr_setup"
require "#{File.dirname(__FILE__)}/../spec_helper"

module Hawkular::Operations::RSpec
  HOST = 'localhost:8080'
  describe 'Websocket connection', :vcr do
    it 'should be established' do
      creds = { username: 'jdoe', password: 'password' }

      client = Hawkular::Operations::OperationsClient.new(HOST, creds)
      ws = client.ws

      # todo: remove the waiting
      sleep 10
      expect(ws).not_to be nil
    end
  end
end
