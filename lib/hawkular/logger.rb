require 'logger'
require 'hawkular/env_config'

module Hawkular
  class Logger
    def initialize(file = STDOUT)
      @logger = ::Logger.new(file)
    end

    def log(message, priority = :info)
      @logger.send(priority, message) if EnvConfig.log_response?
    end
  end
end
