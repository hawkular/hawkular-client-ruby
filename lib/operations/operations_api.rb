require 'hawkular'
require 'websocket-client-simple'

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

    def ws
      @ws
    end

    # Retrieve the tenant id for the passed credentials.
    # If no credentials are passed, the ones from the constructor are used
    # @param credentials [Hash{String=>String}] Hash of username, password, token(optional)
    # @return [String] tenant id
    def get_tokens(credentials = {})
      creds = credentials.empty? ? @credentials : credentials
      auth_header = { Authorization: base_64_credentials(creds) }
      http_get('/secret-store/v1/tokens', auth_header)
    end

    def create_token(credentials = {}, persona = nil, name = 'Token created via Hawkular Ruby Client', expires_at = nil)
      creds = credentials.empty? ? @credentials : credentials
      auth_header = { Authorization: base_64_credentials(creds) }
      auth_header['Hawkular-Persona'] = persona if persona

      token_attributes = { expiresAt: expires_at, attributes: { name: name } }
      http_post('/secret-store/v1/tokens/create', token_attributes, auth_header)
    end
  end
end
