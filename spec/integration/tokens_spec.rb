require "#{File.dirname(__FILE__)}/../vcr/vcr_setup"
require "#{File.dirname(__FILE__)}/../spec_helper"

module Hawkular::Token::RSpec
  HAWKULAR_BASE = 'http://localhost:8080'.freeze
  describe 'Tokens', :vcr do
    it 'Should be able to list the available tokens' do
      creds = { username: 'jdoe', password: 'password' }
      client = Hawkular::Token::TokenClient.new(HAWKULAR_BASE, creds)
      tokens = client.get_tokens(creds)
      expect(tokens).to be_empty
    end

    it 'Should be able to create a new token for an actual user' do
      creds = { username: 'jdoe', password: 'password' }
      client = Hawkular::Token::TokenClient.new(HAWKULAR_BASE, creds)
      token = client.create_token(creds)
      expect(token['key']).not_to be_nil
      expect(token['secret']).not_to be_nil
      expect(token['attributes']['name']).to eq('Token created via Hawkular Ruby Client')
    end

    it 'Should get a 401 when attempting to create a token with a wrong password' do
      creds = { username: 'jdoe', password: 'mywrongpassword' }
      client = Hawkular::Token::TokenClient.new(HAWKULAR_BASE, creds)
      begin
        client.create_token(creds)
        fail 'Should have failed with 401'
      rescue Hawkular::HawkularException => exception
        expect(exception.status_code).to be(401)
      end
    end

    it 'Should get a 401 when attempting to create a token without a password' do
      creds = { username: 'jdoe', password: '' }
      client = Hawkular::Token::TokenClient.new(HAWKULAR_BASE, creds)
      begin
        client.create_token(creds)
        fail 'Should have failed with 401'
      rescue Hawkular::HawkularException => exception
        expect(exception.status_code).to be(401)
      end
    end
  end
end
