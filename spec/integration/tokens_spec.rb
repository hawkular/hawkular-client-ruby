require_relative '../vcr/vcr_setup'
require_relative '../spec_helper'

module Hawkular::Token::RSpec
  HAWKULAR_BASE = 'http://localhost:8080'.freeze
  describe 'Tokens', :vcr do
    it 'Should be able to list the available tokens' do
      creds = { username: 'jdoe', password: 'password' }
      options = { tenant: 'hawkular' }
      client = Hawkular::Token::Client.new(HAWKULAR_BASE, creds, options)
      tokens = client.get_tokens(creds)
      expect(tokens).to be_empty
    end

    it 'Should be able to create a new token for an actual user' do
      creds = { username: 'jdoe', password: 'password' }
      options = { tenant: 'hawkular' }
      client = Hawkular::Token::Client.new(HAWKULAR_BASE, creds, options)
      token = client.create_token(creds)
      expect(token['key']).not_to be_nil
      expect(token['secret']).not_to be_nil
      expect(token['attributes']['name']).to eq('Token created via Hawkular Ruby Client')
    end

    it 'Should get a 401 when attempting to create a token with a wrong password' do
      creds = { username: 'jdoe', password: 'mywrongpassword' }
      options = { tenant: 'hawkular' }
      client = Hawkular::Token::Client.new(HAWKULAR_BASE, creds, options)
      begin
        client.create_token(creds)
        fail 'Should have failed with 401'
      rescue Hawkular::BaseClient::HawkularException => exception
        expect(exception.status_code).to be(401)
      end
    end

    it 'Should get a 401 when attempting to create a token without a password' do
      creds = { username: 'jdoe', password: '' }
      options = { tenant: 'hawkular' }
      client = Hawkular::Token::Client.new(HAWKULAR_BASE, creds, options)
      begin
        client.create_token(creds)
        fail 'Should have failed with 401'
      rescue Hawkular::BaseClient::HawkularException => exception
        expect(exception.status_code).to be(401)
      end
    end
  end
end
