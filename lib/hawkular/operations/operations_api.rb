require 'timeout'
require 'monitor'

require 'hawkular/base_client'
require 'websocket-client-simple'
require 'json'

require 'hawkular/inventory/entities'

# Adding a method `perform` for each block so that we can write nice callbacks for this client
class Proc
  class PerformMethodMissing
  end
  def perform(callable, result)
    call(Class.new do
      method_name = callable.to_sym
      define_method(method_name) { |&block| block.nil? ? true : block.call(result) }
      define_method("#{method_name}?") { true }
      define_method(:method_missing) { |*| PerformMethodMissing }
    end.new)
  end
end

# Operations module allows invoking operation on the WildFly agent.
module Hawkular::Operations
  # Client class to interact with the agent via websockets
  class Client < Hawkular::BaseClient
    include WebSocket::Client
    include MonitorMixin

    attr_accessor :ws, :logger

    # helper for parsing the "OperationName=json_payload" messages
    class WebSocket::Frame::Data
      def to_msg_hash
        operation_name, json = split('=', 2)

        # Check if there is a zip file following JSON.
        # This check is done only in the first 100KB, hoping it's unlikely to
        # have such large amount of JSON before a zip file is attached.
        magic_bits = [
          "\x50\x4B\x03\x04", # "PK" + 0x03 + 0x04 = Regular ZIP file
          "\x50\x4B\x05\x06", # "PK" + 0x05 + 0x06 = Empty ZIP
          "\x50\x4B\x07\x08"  # "PK" + 0x07 + 0x08 = Spanned ZIP
        ]
        search_chunk = json[0, 102_400]
        zip_file = nil

        magic_bits.each do |bits|
          idx = search_chunk.index(bits)

          next unless idx

          zip_file = json[idx..-1]
          json = json[0, idx]
          break
        end

        # Parse JSON and, if received, attach zip file
        json = JSON.parse(json)
        json[:attachments] = zip_file

        # Return processed data
        { operationName: operation_name, data: json }
      rescue
        {}
      end
    end

    # Initialize new Client
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
    #   Hawkular::Operations::Client.new(credentials: {username: 'jdoe', password: 'password'})
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

      fail Hawkular::ArgumentError, 'no parameter ":host" or ":entrypoint" given' if args[:host].nil?

      super(args[:host], args[:credentials], args[:options])

      @logger = Hawkular::Logger.new

      @url = "ws#{args[:use_secure_connection] ? 's' : ''}://#{args[:host]}/hawkular/command-gateway/ui/ws"
      @credentials = args[:credentials]
      @tenant = args[:options][:tenant]
      @wait_time = args[:wait_time]
    end

    def base64_credentials
      ["#{@credentials[:username]}:#{@credentials[:password]}"].pack('m').delete("\r\n")
    end

    def connect
      return if @connecting || (@ws && @ws.open?)

      @connecting = true

      ws_options = {
        headers:  {
          'Authorization' => 'Basic ' + base64_credentials,
          'Hawkular-Tenant' => @tenant,
          'Accept' => 'application/json'
        }
      }

      @ws = Simple.connect @url, ws_options do |client|
        client.on(:message, once: true) do |msg|
          parsed_message = msg.data.to_msg_hash

          logger = Hawkular::Logger.new
          logger.log("Sent WebSocket message: #{parsed_message}")
        end
      end

      Timeout.timeout(@wait_time) { sleep 0.1 until @ws.open? }
    ensure
      @connecting = false
    end

    # Closes the WebSocket connection
    def close_connection!
      @ws && @ws.close
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
      fail Hawkular::ArgumentError, 'Operation must be specified' if operation_name.nil?
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
      fail Hawkular::ArgumentError, 'resource_path must be specified' if resource_path.nil?
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
      synchronize { connect }

      # fallback to generic 'ExecuteOperation' if nothing is specified
      operation_name ||= 'ExecuteOperation'
      add_credentials! operation_payload

      handle_message(operation_name, operation_payload, &callback) unless callback.nil?

      # sends a message that will actually run the operation
      payload = "#{operation_name}Request=#{operation_payload.to_json}"
      payload += binary_content unless binary_content.nil?
      @ws.send payload, type: binary_content.nil? ? :text : :binary
    rescue => e
      callback.perform(:failure, "#{e.class} - #{e.message}")
    end

    def check_pre_conditions(hash = {}, params = [], &callback)
      fail Hawkular::ArgumentError, 'Hash cannot be nil.' if hash.nil?
      fail Hawkular::ArgumentError, 'callback must have the perform method defined. include Hawkular::Operations' unless
          callback.nil? || callback.respond_to?('perform')

      params.each do |property|
        next unless hash[property].nil?
        err_callback = 'You need to specify error callback'
        err_message = "Hash property #{property} must be specified"

        if !callback || callback.perform(:failure, err_message) == Proc::PerformMethodMissing
          fail(Hawkular::ArgumentError, err_callback)
        end
      end
    end

    def add_credentials!(hash)
      hash[:authentication] = @credentials.delete_if { |_, v| v.nil? }
    end

    def handle_message(operation_name, operation_payload, &callback)
      client = @ws
      # register a callback handler
      @ws.on :message do |msg|
        parsed = msg.data.to_msg_hash

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
          Client.handle_error parsed, &callback
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
end
