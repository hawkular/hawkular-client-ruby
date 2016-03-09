require 'hawkular'
require 'websocket-client-simple'
require 'json'

# Adding a method `perform` for each block so that we can write nice callbacks for this client
class Proc
  def perform(callable, result)
    call(Class.new do
      method_name = callable.to_sym
      define_method(method_name) { |&block| block.nil? ? true : block.call(result) }
      define_method("#{method_name}?") { true }
      # method_missing is here because we are not forcing the client to provide both success and error callbacks
      # rubocop:disable Lint/NestedMethodDefinition
      # https://github.com/bbatsov/rubocop/issues/2704
      def method_missing(_method_name, *_args, &_block)
        false
      end
      # rubocop:enable Lint/NestedMethodDefinition
    end.new)
  end
end

# Operations module allows invoking operation on the wildfly agent.
module Hawkular::Operations
  # Client class to interact with the agent via websockets
  class OperationsClient < Hawkular::BaseClient
    include WebSocket::Client

    attr_accessor :ws

    # helper for parsing the "OperationName=json_payload" messages
    class WebSocket::Frame::Data
      def to_msg_hash
        hash = {}
        chunks = split('=', 2)
        hash[:operationName] = chunks[0]
        hash[:data] = JSON.parse(chunks[1])
        hash
      rescue
        {}
      end
    end

    # Create a new OperationsClient
    # @param hash [Hash{String=>Object}] a hash containing: host [String] base url of Hawkular -
    # e.g http://localhost:8080
    # and credentials [Hash{String=>String}] Hash of {username, password} or token
    def initialize(hash)
      hash[:host] ||= 'localhost:8080'
      hash[:credentials] ||= {}
      super(hash[:host], hash[:credentials])
      # note: if we start using the secured WS, change the protocol to wss://
      url = "ws://#{entrypoint}/hawkular/command-gateway/ui/ws"
      @ws = Simple.connect url do |client|
        client.on :message do |msg|
          parsed_message = msg.data.to_msg_hash
          puts parsed_message if ENV['HAWKULARCLIENT_LOG_RESPONSE']
          case parsed_message[:operationName]
          when 'WelcomeResponse'
            @session_id = parsed_message[:data]['sessionId']
            client.remove_listener :message
          end
        end
      end
      sleep 1
    end

    # Closes the WebSocket connection
    def close_connection!
      @ws.close
    end

    # Invokes a generic operation on the Wildfly agent
    # (the operation name must be specified in the operation_payload hash)
    # Note: if success and failure callbacks are omitted the client will not wait for the Response message
    # @param operation_payload [Hash{String=>Object}] a hash containing: resourcePath [String] denoting the resource on
    # which the operation is about to run, operationName [String]
    # and the credentials [Hash{String=>String}] Hash of {username, password} or token
    # @param block [OperationCallback] callback that after the operation is done
    def invoke_generic_operation(operation_payload, &block)
      fail 'Handshake with server has not been done.' unless @ws.open?
      fail 'Operation must be specified' if operation_payload.nil? || operation_payload[:operationName].nil?
      fail 'block must have the perform method defined. include Hawkular::Operations' unless
          block.nil? || block.respond_to?('perform')

      invoke_operation_helper(operation_payload, nil, &block)
    end

    # Invokes operation on the wildfly agent that has it's own message type
    # @param operation_payload [Hash{String=>Object}] a hash containing: resourcePath [String] denoting
    # the resource on which the operation is about to run
    # and the credentials [Hash{String=>String}] Hash of {username, password} or token
    # @param operation_name [String] the name of the operation. This must correspond with the message type, they can be
    # found here https://git.io/v2h1a (Use only the first part of the name without the Request/Response suffix), e.g.
    # RemoveDatasource (and not RemoveDatasourceRequest)
    # @param block [OperationCallback] callback that after the operation is done
    def invoke_specific_operation(operation_payload, operation_name, &block)
      fail 'Handshake with server has not been done.' unless @ws.open?
      fail 'Operation must be specified' if operation_payload.nil? || operation_name.nil?
      fail 'block must have the perform method defined. include Hawkular::Operations' unless
          block.nil? || block.respond_to?('perform')

      invoke_operation_helper(operation_payload, operation_name, &block)
    end

    private

    # rubocop:disable Metrics/CyclomaticComplexity
    # rubocop:disable Metrics/BlockNesting
    def invoke_operation_helper(operation_payload, operation_name = nil, &block)
      # fallback to generic 'ExecuteOperation' if nothing is specified
      operation_name ||= 'ExecuteOperation'

      # register a callback handler for this operation
      @ws.on :message do |msg|
        parsed = msg.data.to_msg_hash
        # TODO: do this on the WS client lvl and also for client -> server comm
        # puts "\nreceived WebSocket msg: #{parsed}\n" if ENV['HAWKULARCLIENT_LOG_RESPONSE']
        case parsed[:operationName]
        when "#{operation_name}Response"
          same_path = parsed[:data]['resourcePath'] == operation_payload[:resourcePath]
          # failed operations don't return the operation name from some strange reason
          same_name = parsed[:data]['operationName'] == operation_payload[:operationName]
          if same_path # using the resource path as a correlation id
            success = same_name && parsed[:data]['status'] == 'OK'
            success ? block.perform(:success, parsed[:data]) : block.perform(:failure, parsed[:data]['message'])
            client.remove_listener :message
          end
        when 'GenericErrorResponse'
          failure.call(parsed == {} ? 'error' : parsed[:data]['errorMessage'])
          client.remove_listener :message
        end
      end unless block.nil?

      # sends a message that will actually run the operation
      @ws.send "#{operation_name}Request=#{operation_payload.to_json}"
    end
    # rubocop:enable Metrics/CyclomaticComplexity
    # rubocop:enable Metrics/BlockNesting
  end
end
