require 'hawkular/base_client'

# Token module provides access to the Secret Store REST API.
module Hawkular::Token
  # Client class to interact with the Secret Store
  class TokenClient < Hawkular::BaseClient
    # Create a new Secret Store client
    # @param entrypoint [String] base url of Hawkular - e.g http://localhost:8080
    # @param credentials [Hash{String=>String}] Hash of username, password
    # @param options [Hash{String=>String}] Additional rest client options
    def initialize(entrypoint = 'http://localhost:8080', credentials = {}, options = {})
      super(entrypoint, credentials, options)
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
