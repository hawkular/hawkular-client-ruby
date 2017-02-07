require "#{File.dirname(__FILE__)}/../spec_helper"
require 'hawkular/logger'

describe Hawkular::Logger do
  let(:file) { Tempfile.new('hawkular_spec') }
  subject(:logger) { described_class.new(file) }

  describe '#log' do
    before { allow(Hawkular::EnvConfig).to receive(:log_response?) { true } }

    it 'logs the message to a file' do
      logger.log("this is a message")
      file.flush

      expect(File.read(file)).to include "this is a message"
    end

    it 'does not log anything if the config does not allow it' do
      allow(Hawkular::EnvConfig).to receive(:log_response?) { false }

      logger.log("this is a message")
      file.flush

      expect(File.read(file)).to be_empty
    end

    %w(debug info warn error fatal).each do |priority|
      it "allows to log with #{priority} priority" do
        logger.log("this is a message", priority)
        file.flush

        expect(File.read(file)).to include priority.upcase
      end
    end
  end
end
