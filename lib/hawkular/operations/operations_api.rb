require 'hawkular/base_client'
require 'json'
require 'hawkular/inventory/entities'
require 'hawkular/websocket_client'

# Adding a method `perform` for each block so that we can write nice callbacks for this client
class Proc
  class PerformMethodMissing
  end
  def perform(callable, result)
    call(Class.new do
      method_name = callable.to_sym
      define_method(method_name) { |&block| block.nil? ? true : block.call(result) }
      define_method("#{method_name}?") { true }

      # method_missing is here because we are not forcing the client to provide both success and error callbacks
      # rubocop:disable Lint/NestedMethodDefinition
      # https://github.com/bbatsov/rubocop/issues/2704
      def method_missing(_method_name, *_args, &_block)
        PerformMethodMissing
      end
      # rubocop:enable Lint/NestedMethodDefinition
    end.new)
  end
end

# Operations module allows invoking operation on the WildFly agent.
module Hawkular::Operations
  # Client class to interact with the agent via websockets
  class Client < Hawkular::BaseClient
    attr_accessor :ws, :session_id, :logger

    def msg_to_hash(data)
      chunks = data.split('=', 2)
      { operationName: chunks[0], data: JSON.parse(chunks[1]) }
    rescue
      {}
    end

    # Initialize new OperationsClient
    #
    # @param [Hash] args Arguments for client.
    # There are two ways of passing in the target host/port: via :host and via :entrypoint. If
    # both are given, then :entrypoint will be used.
    #
    # @option args [String] :entrypoint Base URL of the hawkular server e.g. http://localhost:8080.
    # @option args [String] :host base host:port pair of Hawkular - e.g localhost:8080
    # @option args [Boolean] :use_secure_connection if no entrypoint is provided, determines if use a secure connection
    #                        defaults to false
    # @option args [Hash{String=>String}]  :credentials Hash of (username password) or token
    # @option args [Hash{String=>String}] :options Additional rest client options
    # @option args [Fixnum]  :wait_time Time in seconds describing how long the constructor should block - handshake
    #
    # @example
    #   Hawkular::Operations::OperationsClient.new(credentials: {username: 'jdoe', password: 'password'})
    def initialize(args)
      args = {
        credentials: {},
        options: {},
        wait_time: 0.5,
        use_secure_connection: false,
        entrypoint: nil
      }.merge(args)

      if args[:entrypoint]
        uri = URI.parse(args[:entrypoint].to_s)
        args[:host] = "#{uri.host}:#{uri.port}"
        args[:use_secure_connection] = %w(https wss).include?(uri.scheme) ? true : false
      end

      fail 'no parameter ":host" or ":entrypoint" given' if args[:host].nil?

      super(args[:host], args[:credentials], args[:options])

      url = "ws#{args[:use_secure_connection] ? 's' : ''}://#{args[:host]}/hawkular/command-gateway/ui/ws"

      creds = args[:credentials]
      base64_creds = ["#{creds[:username]}:#{creds[:password]}"].pack('m').delete("\r\n")

      ws_options = {
        headers: {
          'Authorization' => 'Basic ' + base64_creds,
          'Hawkular-Tenant' => args[:options][:tenant],
          'Accept' => 'application/json'
        }
      }

      @logger = Hawkular::Logger.new
      logger = @logger
      op_api = self
      @ws = Hawkular::WebsocketClient.connect url, ws_options do |client|
        client.on(:message, once: true) do |msg|
          parsed_message = op_api.msg_to_hash msg

          logger.log("Sent WebSocket message: #{parsed_message}")

          case parsed_message[:operationName]
          when 'WelcomeResponse'
            op_api.session_id = parsed_message[:data]['sessionId']
          end
        end
      end

      sleep args[:wait_time]
    end

    # Closes the WebSocket connection
    def close_connection!
      @ws.close
    end

    # Invokes a generic operation on the WildFly agent
    # (the operation name must be specified in the hash)
    # Note: if success and failure callbacks are omitted, the client will not wait for the Response message
    # @param hash [Hash{String=>Object}] a hash containing: resourcePath [String] denoting the resource on
    # which the operation is about to run, operationName [String]
    # @param callback [Block] callback that is run after the operation is done
    def invoke_generic_operation(hash, &callback)
      required = [:resourcePath, :operationName]
      check_pre_conditions hash, required, &callback

      invoke_operation_helper(hash, &callback)
    end

    # Invokes operation on the WildFly agent that has it's own message type
    # @param operation_payload [Hash{String=>Object}] a hash containing: resourcePath [String] denoting
    # the resource on which the operation is about to run
    # @param operation_name [String] the name of the operation. This must correspond with the message type, they can be
    # found here https://git.io/v2h1a (Use only the first part of the name without the Request/Response suffix), e.g.
    # RemoveDatasource (and not RemoveDatasourceRequest)
    # @param callback [Block] callback that is run after the operation is done
    def invoke_specific_operation(operation_payload, operation_name, &callback)
      fail 'Operation must be specified' if operation_name.nil?
      required = [:resourcePath]
      check_pre_conditions operation_payload, required, &callback

      invoke_operation_helper(operation_payload, operation_name, &callback)
    end

    # Deploys an archive file into WildFly
    #
    # @param [Hash] hash Arguments for deployment
    # @option hash [String]  :resource_path canonical path of the WildFly server into which we deploy
    #                        or of the domain controller if we deploy into a server group (in case of domain mode)
    # @option hash [String]  :destination_file_name resulting file name
    # @option hash [String]  :binary_content binary content representing the war file
    # @option hash [String]  :enabled whether the deployment should be enabled immediately, or not (default = true)
    # @option hash [String]  :force_deploy whether to replace existing content or not (default = false)
    # @option hash [String]  :server_groups comma-separated list of server groups for the operation (default = ignored)
    #
    # @param callback [Block] callback that is run after the operation is done
    def add_deployment(hash, &callback)
      hash[:enabled] = hash.key?(:enabled) ? hash[:enabled] : true
      hash[:force_deploy] = hash.key?(:force_deploy) ? hash[:force_deploy] : false
      required = [:resource_path, :destination_file_name, :binary_content]
      check_pre_conditions hash, required, &callback

      operation_payload = prepare_payload_hash([:binary_content], hash)
      invoke_operation_helper(operation_payload, 'DeployApplication', hash[:binary_content], &callback)
    end

    # Undeploy a WildFly deployment
    #
    # @param [Hash] hash Arguments for deployment removal
    # @option hash [String]  :resource_path canonical path of the WildFly server from which to undeploy the deployment
    # @option hash [String]  :deployment_name name of deployment to undeploy
    # @option hash [String]  :remove_content whether to remove the deployment content or not (default = true)
    # @option hash [String]  :server_groups comma-separated list of server groups for the operation (default = ignored)
    #
    # @param callback [Block] callback that is run after the operation is done
    def undeploy(hash, &callback)
      hash[:remove_content] = hash.key?(:remove_content) ? hash[:remove_content] : true
      required = [:resource_path, :deployment_name]
      check_pre_conditions hash, required, &callback

      cp = ::Hawkular::Inventory::CanonicalPath.parse hash[:resource_path]
      server_path = cp.up.to_s
      hash[:resource_path] = server_path
      hash[:destination_file_name] = hash[:deployment_name]

      operation_payload = prepare_payload_hash([:deployment_name], hash)
      invoke_operation_helper(operation_payload, 'UndeployApplication', &callback)
    end

    # @deprecated Please use undeploy() instead
    def remove_deployment(hash, &callback)
      undeploy(hash, &callback)
    end

    # Enable a WildFly deployment
    #
    # @param [Hash] hash Arguments for enable deployment
    # @option hash [String]  :resource_path canonical path of the WildFly server from which to enable the deployment
    # @option hash [String]  :deployment_name name of deployment to enable
    # @option hash [String]  :server_groups comma-separated list of server groups for the operation (default = ignored)
    #
    # @param callback [Block] callback that is run after the operation is done
    def enable_deployment(hash, &callback)
      required = [:resource_path, :deployment_name]
      check_pre_conditions hash, required, &callback

      cp = ::Hawkular::Inventory::CanonicalPath.parse hash[:resource_path]
      server_path = cp.up.to_s
      hash[:resource_path] = server_path
      hash[:destination_file_name] = hash[:deployment_name]

      operation_payload = prepare_payload_hash([:deployment_name], hash)
      invoke_operation_helper(operation_payload, 'EnableApplication', &callback)
    end

    # Disable a WildFly deployment
    #
    # @param [Hash] hash Arguments for disable deployment
    # @option hash [String]  :resource_path canonical path of the WildFly server from which to disable the deployment
    # @option hash [String]  :deployment_name name of deployment to disable
    # @option hash [String]  :server_groups comma-separated list of server groups for the operation (default = ignored)
    #
    # @param callback [Block] callback that is run after the operation is done
    def disable_deployment(hash, &callback)
      required = [:resource_path, :deployment_name]
      check_pre_conditions hash, required, &callback

      cp = ::Hawkular::Inventory::CanonicalPath.parse hash[:resource_path]
      server_path = cp.up.to_s
      hash[:resource_path] = server_path
      hash[:destination_file_name] = hash[:deployment_name]

      operation_payload = prepare_payload_hash([:deployment_name], hash)
      invoke_operation_helper(operation_payload, 'DisableApplication', &callback)
    end

    # Restart a WildFly deployment
    #
    # @param [Hash] hash Arguments for restart deployment
    # @option hash [String]  :resource_path canonical path of the WildFly server from which to restart the deployment
    # @option hash [String]  :deployment_name name of deployment to restart
    # @option hash [String]  :server_groups comma-separated list of server groups for the operation (default = ignored)
    #
    # @param callback [Block] callback that is run after the operation is done
    def restart_deployment(hash, &callback)
      required = [:resource_path, :deployment_name]
      check_pre_conditions hash, required, &callback

      cp = ::Hawkular::Inventory::CanonicalPath.parse hash[:resource_path]
      server_path = cp.up.to_s
      hash[:resource_path] = server_path
      hash[:destination_file_name] = hash[:deployment_name]

      operation_payload = prepare_payload_hash([:deployment_name], hash)
      invoke_operation_helper(operation_payload, 'RestartApplication', &callback)
    end

    # Adds a new datasource
    #
    # @param [Hash] hash Arguments for the datasource
    # @option hash [String]  :resourcePath canonical path of the WildFly server into which we add datasource
    # @option hash [String]  :xaDatasource XA DS or normal
    # @option hash [String]  :datasourceName name of the datasource
    # @option hash [String]  :jndiName JNDI name
    # @option hash [String]  :driverName this is internal name of the driver in Hawkular
    # @option hash [String]  :driverClass class of driver
    # @option hash [String]  :connectionUrl jdbc connection string
    # @option hash [String]  :datasourceProperties optional properties
    # @option hash [String]  :username username to DB
    # @option hash [String]  :password password to DB
    #
    # @param callback [Block] callback that is run after the operation is done
    def add_datasource(hash, &callback)
      required = [:resourcePath, :xaDatasource, :datasourceName, :jndiName, :driverName, :driverClass, :connectionUrl]
      check_pre_conditions hash, required, &callback

      invoke_specific_operation(hash, 'AddDatasource', &callback)
    end

    # Adds a new datasource
    #
    # @param [Hash] hash Arguments for the datasource
    # @option hash [String]  :resource_path canonical path of the WildFly server into which we add driver
    # @option hash [String]  :driver_jar_name name of the jar file
    # @option hash [String]  :driver_name name of the jdbc driver (when adding datasource, this is the driverName)
    # @option hash [String]  :module_name name of the JBoss module into which the driver will be installed - 'foo.bar'
    # @option hash [String]  :driver_class fully specified java class of the driver - e.q. 'com.mysql.jdbc.Driver'
    # @option hash [String]  :binary_content driver jar file bits
    #
    # @param callback [Block] callback that is run after the operation is done
    def add_jdbc_driver(hash, &callback)
      required = [:resource_path, :driver_jar_name, :driver_name, :module_name, :driver_class, :binary_content]
      check_pre_conditions hash, required, &callback

      operation_payload = prepare_payload_hash([:binary_content], hash)
      invoke_operation_helper(operation_payload, 'AddJdbcDriver', hash[:binary_content], &callback)
    end

    # Exports the JDR report
    #
    # @param [String] resource_path canonical path of the WildFly server
    # @param callback [Block] callback that is run after the operation is done
    def export_jdr(resource_path, &callback)
      fail 'resource_path must be specified' if resource_path.nil?
      check_pre_conditions(&callback)

      invoke_specific_operation({ resourcePath: resource_path }, 'ExportJdr', &callback)
    end

    # Updates the collection intervals.
    #
    # @param [Hash] hash Arguments for update collection intervals
    # @option hash {resourcePath} a resource managed by the target agent
    # @option hash {metricTypes} A map with key=MetricTypeId, value=interval (seconds).
    # MetricTypeId must be of form MetricTypeSet~MetricTypeName
    # @option hash {availTypes} A map with key=AvailTypeId, value=interval (seconds).
    # AvailTypeId must be of form AvailTypeSet~AvailTypeName
    #
    # @param callback [Block] callback that is run after the operation is done
    def update_collection_intervals(hash, &callback)
      required = [:resourcePath, :metricTypes, :availTypes]
      check_pre_conditions hash, required, &callback
      invoke_specific_operation(hash, 'UpdateCollectionIntervals', &callback)
    end

    private

    def invoke_operation_helper(operation_payload, operation_name = nil, binary_content = nil, &callback)
      # fallback to generic 'ExecuteOperation' if nothing is specified
      operation_name ||= 'ExecuteOperation'
      add_credentials! operation_payload

      handle_message(operation_name, operation_payload, &callback) unless callback.nil?

      # sends a message that will actually run the operation
      payload = "#{operation_name}Request=#{operation_payload.to_json}"
      unless binary_content.nil?
        payload += binary_content
        payload = payload.bytes.to_a
      end
      @ws.send payload
    end

    def check_pre_conditions(hash = {}, params = [], &callback)
      fail 'Handshake with server has not been done.' unless @ws.open?
      fail 'Hash cannot be nil.' if hash.nil?
      fail 'callback must have the perform method defined. include Hawkular::Operations' unless
          callback.nil? || callback.respond_to?('perform')
      params.each do |property|
        next unless hash[property].nil?
        err_callback = 'You need to specify error callback'
        err_message = "Hash property #{property} must be specified"
        fail(ArgumentError, err_callback) if callback.nil?
        fail(ArgumentError, err_callback) if callback.perform(:failure, err_message).equal? Proc::PerformMethodMissing
      end
    end

    def add_credentials!(hash)
      hash[:authentication] = @credentials.delete_if { |_, v| v.nil? }
    end

    def handle_message(operation_name, operation_payload, &callback)
      client = @ws
      op_api = self
      # register a callback handler
      @ws.on :message do |msg|
        parsed = op_api.msg_to_hash(msg.data)

        logger = Hawkular::Logger.new
        logger.log("Received WebSocket msg: #{parsed}")

        case parsed[:operationName]
        when "#{operation_name}Response"
          same_path = parsed[:data]['resourcePath'] == operation_payload[:resourcePath]
          # failed operations don't return the operation name from some strange reason
          same_name = operation_payload[:operationName].nil? ||
                      parsed[:data]['operationName'] == operation_payload[:operationName].to_s
          if same_path # using the resource path as a correlation id
            success = same_name && parsed[:data]['status'] == 'OK'
            success ? callback.perform(:success, parsed[:data]) : callback.perform(:failure, parsed[:data]['message'])
            client.remove_listener :message
          end
        when 'GenericErrorResponse'
          OperationsClient.handle_error parsed, &callback
          client.remove_listener :message
        end
      end
    end

    def self.handle_error(parsed_message, &callback)
      callback.perform(:failure, parsed_message == {} ? 'error' : parsed_message[:data]['errorMessage'])
    end

    def prepare_payload_hash(ignored_params, hash)
      # it filters out ignored params and convert keys from snake_case to camelCase
      Hash[hash.select { |k, _| !ignored_params.include? k }.map { |k, v| [to_camel_case(k.to_s).to_sym, v] }]
    end

    def to_camel_case(str)
      ret = str.split('_').collect(&:capitalize).join
      ret[0, 1].downcase + ret[1..-1]
    end
  end

  OperationsClient = Client
  deprecate_constant :OperationsClient if self.respond_to? :deprecate_constant
end
