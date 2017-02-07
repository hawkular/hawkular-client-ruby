require "#{File.dirname(__FILE__)}/../spec_helper"
require 'hawkular/env_config'

describe Hawkular::EnvConfig do
  subject(:config) { Hawkular::EnvConfig }
  describe '.log_response?' do
    it 'is true if defined' do
      swap_env('HAWKULARCLIENT_LOG_RESPONSE', 'true') do
        expect(config.log_response?).to be true
      end
    end

    it 'is false if null' do
      swap_env('HAWKULARCLIENT_LOG_RESPONSE', nil) do
        expect(config.log_response?).to be false
      end
    end
  end

  describe '.rest_timeout' do
    it 'returns the value for the environment' do
      swap_env('HAWKULARCLIENT_REST_TIMEOUT', '20') do
        expect(config.rest_timeout).to eq '20'
      end
    end
  end

  private

  def swap_env(name, value)
    old_value = ENV[name]
    ENV[name] = value

    yield
  ensure
    ENV[name] = old_value
  end
end
