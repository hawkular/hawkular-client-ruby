require 'event_emitter'
require 'eventmachine'
require 'faye/websocket'

module Hawkular
  class WebsocketClient
    include EventEmitter
    @channel = EventMachine::Channel.new
    attr_accessor :url, :ws, :open, :options, :thread
    attr_reader :open
    alias_method :open?, :open
    class << self
      attr_accessor :channel
    end

    def self.connect(url, options = {})
      client = Hawkular::WebsocketClient.new
      yield client if block_given?
      client.connect url, options
      client
    end

    def connect(url, options = {}, timeout = 60)
      uri = URI.parse(url)
      @open = false
      if uri.host == 'localhost'
        uri.host = '127.0.0.1'
        url = uri.to_s
      end
      @url = url
      @options = options
      @timeout = timeout
      self.class.send :running_thread
      self.class.channel.push(self)
      @thread = Thread.current
      sleep(@timeout)
      emit :error unless @open
    end

    def send(message)
      @ws.send message
    end

    def close
      return unless @open
      @ws.close
      sleep(@timeout)
    end

    def self.running_thread
      return if EventMachine.reactor_running?
      Thread.new do
        EventMachine.run do
          @channel.subscribe do |client|
            ws = Faye::WebSocket::Client.new(client.url, [], client.options)
            client.ws = ws
            ws.onopen = lambda do |_event|
              client.open = true
              client.thread.wakeup
              client.emit :open
            end
            ws.onclose = lambda do |_event|
              client.open = false
              client.thread.wakeup
            end
            ws.onerror = lambda do |error|
              client.emit :error, error.message
            end
            ws.onmessage = lambda do |message|
              begin
                client.emit :message, message
              rescue => exception
                p exception
                puts exception.backtrace
              end
            end
          end
        end
      end
    end
    private_class_method :running_thread
  end
end
