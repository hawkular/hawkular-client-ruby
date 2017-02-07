require 'logger'
require 'hawkular/env_config'

module Hawkular
  class Logger
    def initialize(file = STDOUT)
      @logger = ::Logger.new(file)
    end

    def log(message, priority = :info)
      return unless EnvConfig.log_response?

      @logger.send(priority, message)
    end
  end
end
