require 'hawkular'
require 'websocket-client-simple'
require 'json'

class Proc
  def perform(callable, result)
    call(Class.new do
      method_name = callable.to_sym
      define_method(method_name) { |&block| block.nil? ? true : block.call(result) }
      define_method("#{method_name}?") { true }
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

    # Create a new OperationsClient
    # @param entrypoint [String] base url of Hawkular - e.g http://localhost:8080
    # @param credentials [Hash{String=>String}] Hash of {username, password} or token
    def initialize(entrypoint = nil, credentials = {})
      super(entrypoint, credentials)
      url = "ws://#{entrypoint}/hawkular/command-gateway/ui/ws"
      @ws = WebSocket::Client::Simple.connect url
      # todo: once the socket is open, the server sends to client its ui session id, we need to store it here
      @ws.on :open do
        @ws.send 'Make me a sandwich'
      end
    end

    # Invokes a generic operation on the Wildfly agent
    # (the operation name must be specified in the operation_payload hash)
    # Note: if success and failure callbacks are omitted the client will not wait for the Response message
    # @param operation_payload [Hash{String=>Object}] a hash containing: resourcePath [String] denoting the resource on
    # which the operation is about to run, operationName [String]
    # and the credentials [Hash{String=>String}] Hash of {username, password} or token
    # @param block [Block] callback that after the operation is done
    def invoke_generic_operation(operation_payload, &block)
      fail 'Handshake with server has not been done.' unless @ws.open?
      fail 'Operation must be specified' if operation_payload.nil? || operation_payload[:operationName].nil?
      invoke_operation_helper(operation_payload, nil, &block)
    end

    # Invokes operation on the wildfly agent that has it's own message type
    # @param operation_payload [Hash{String=>Object}] a hash containing: resourcePath [String] denoting
    # the resource on which the operation is about to run
    # and the credentials [Hash{String=>String}] Hash of {username, password} or token
    # @param operation_name [String] the name of the operation. This must correspond with the message type, they can be
    # found here https://git.io/v2h1a (Use only the first part of the name without the Request/Response suffix), e.g.
    # RemoveDatasource (and not RemoveDatasourceRequest)
    # @param block [Block] callback that after the operation is done
    def invoke_specific_operation(operation_payload, operation_name, &block)
      fail 'Handshake with server has not been done.' unless @ws.open?
      fail 'Operation must be specified' if operation_payload.nil? || operation_name.nil?
      invoke_operation_helper(operation_payload, operation_name, &block)
    end

    # def add_deployment(resourcePath, destinationFileName, fileBinaryContent, enabled, success, failure)
    #   fail 'Handshake with server has not been done.' unless ws.open?
    #   fail 'resourcePath must be specified' if resourcePath.nil?
    #   fail 'destinationFileName must be specified' if destinationFileName.nil?
    #   fail 'fileBinaryContent must be specified' if fileBinaryContent.nil?
    #   fail 'enabled must be specified' if enabled.nil?
    #
    #   # register a callback handler for this operation
    #   @ws.on :message do |msg|
    #     puts 'NEW MESSAGE FROM WEBSOCKET2:'
    #     parsed = msg.data.to_msg_hash
    #     # https://github.com/hawkular/hawkular-ui-services/blob/master/src/rest/hawkRest-ops-factory.ts
    #     # DeployApplicationResponse , GenericSuccessResponse, AddJdbcDriverResponse, RemoveJdbcDriverResponse,
    # AddDatasourceResponse, UpdateDatasourceResponse, RemoveDatasourceResponse, ExportJdrResponse, GenericErrorResponse
    #     case parsed[:operationName]
    #       when 'ExecuteOperationResponse'
    #         if parsed[:data]['operationName'] == operation[:operationName] &&
    #            parsed[:data]['resourcePath'] == operation[:resourcePath]
    #           status == 'OK' ? success.(parsed[:data]) : failure.(parsed[:data]['message'])
    #         end
    #       when 'ExecuteOperationResponse'
    #         success.(parsed[:data]['message'])
    #       when 'GenericErrorResponse'
    #         failure.(parsed[:data]['errorMessage'])
    #     end
    #   end if !success.nil? && !failure.nil?
    #
    #   operation = {
    #       resourcePath: resourcePath,
    #       destinationFileName: destinationFileName,
    #       enabled: enabled,
    #       authentication: @credentials
    #   }
    #   # sends a message that will actually run the operation
    #   @ws.send "DeployApplicationRequest=#{operation.to_json}#{fileBinaryContent}"
    #                .force_encoding("ASCII-8BIT")
    #                .bytes.to_a
    # end

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
        # https://github.com/hawkular/hawkular-ui-services/blob/master/src/rest/hawkRest-ops-factory.ts
        # https://git.io/v2h1a
        # DeployApplicationResponse , GenericSuccessResponse, AddJdbcDriverResponse, RemoveJdbcDriverResponse,
        # AddDatasourceResponse, UpdateDatasourceResponse, RemoveDatasourceResponse, ExportJdrResponse,
        # GenericErrorResponse
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

      token_attributes = { expiresAt: expires_at, attributes: { name: name } }
      http_post('/secret-store/v1/tokens/create', token_attributes, auth_header)
    end
    # rubocop:enable Metrics/CyclomaticComplexity
    # rubocop:enable Metrics/BlockNesting
  end
end
