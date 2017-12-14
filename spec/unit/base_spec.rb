require_relative '../vcr/vcr_setup'
require_relative '../spec_helper'

describe 'Base Spec' do
  it 'should know encode' do
    creds = { username: 'jdoe', password: 'password' }

    c = Hawkular::BaseClient.new('not-needed-for-this-test')
    val = c.base_64_credentials(creds)

    expect(val).to eql('amRvZTpwYXNzd29yZA==')
  end

  it 'should be empty' do
    c = Hawkular::BaseClient.new('not-needed-for-this-test')
    ret = c.generate_query_params
    expect(ret).to eql('')
  end

  it 'should have one param' do
    params = { name: nil, value: 'hello' }

    c = Hawkular::BaseClient.new('not-needed-for-this-test')
    ret = c.generate_query_params params

    expect(ret).to eql('?value=hello')
  end

  it 'should have two params' do
    params = { name: 'world', value: 'hello' }

    c = Hawkular::BaseClient.new('not-needed-for-this-test')
    ret = c.generate_query_params params

    expect(ret).to include('value=hello')
    expect(ret).to include('name=world')
    expect(ret).to start_with('?')
    expect(ret).to include('&')
  end

  it 'should flatten arrays' do
    params = { value: %w[hello world] }

    c = Hawkular::BaseClient.new('not-needed-for-this-test')
    ret = c.generate_query_params params

    expect(ret).to eql('?value=hello,world')
  end

  it 'should flatten arrays2' do
    params = { value: [] }

    c = Hawkular::BaseClient.new('not-needed-for-this-test')
    ret = c.generate_query_params params

    expect(ret).to eq('')
  end

  it 'should escape numbers' do
    c = Hawkular::BaseClient.new('not-needed-for-this-test')
    ret = c.hawk_escape 12_345

    expect(ret).to eq('12345')
  end

  it 'should escape alpha' do
    c = Hawkular::BaseClient.new('not-needed-for-this-test')
    ret = c.hawk_escape 'a12345'

    expect(ret).to eq('a12345')
  end

  it 'should escape strange stuff' do
    c = Hawkular::BaseClient.new('not-needed-for-this-test')
    ret = c.hawk_escape 'a1%2 3|45/'

    expect(ret).to eq('a1%252%203%7c45%2f')
  end

  it 'should pass through options to rest_client' do
    proxy_uri = 'http://myproxy.com'
    c = Hawkular::BaseClient.new('not-needed-for-this-test', {},
                                 { proxy: proxy_uri, timeout: 10 })
    rc = c.rest_client('myurl')

    expect(rc.options).to include(proxy: proxy_uri, timeout: 10)
  end

  # backward compatibility
  it 'should pass :http_proxy_uri to rest_client :proxy' do
    proxy_uri = 'http://myproxy.com'
    c = Hawkular::BaseClient.new('not-needed-for-this-test', {},
                                 { http_proxy_uri: proxy_uri })
    rc = c.rest_client('myurl')

    expect(rc.options[:proxy]).to eq(proxy_uri)
    expect(rc.options).to include(proxy: proxy_uri)
    expect(rc.options).not_to have_key(:http_proxy_uri)
  end

  it 'should merge constructor, hawkular, and call headers' do
    c = Hawkular::BaseClient.new('not-needed-for-this-test', {},
                                 { tenant: 'Me', headers: { 'X-Foo' => 'bar' } })
    headers = c.http_headers('Referer' => 'them.example.com')

    expect(headers).to include('Hawkular-Tenant': 'Me',
                               'Referer' => 'them.example.com',
                               'X-Foo' => 'bar')
  end

  it 'Should normalize different types of url and suffix combinations with or without slash' do
    c = Hawkular::BaseClient.new('not-needed-for-this-test')

    ret = c.normalize_entrypoint_url 'http://localhost:8080', '/hawkular/alerts/'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080', '/hawkular/alerts'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080', 'hawkular/alerts/'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080', 'hawkular/alerts'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/', '/hawkular/alerts/'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/', '/hawkular/alerts'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/', 'hawkular/alerts/'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/', 'hawkular/alerts'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/hawkular/alerts', '/hawkular/alerts/'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/hawkular/alerts', '/hawkular/alerts'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/hawkular/alerts', 'hawkular/alerts/'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/hawkular/alerts', 'hawkular/alerts'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/hawkular/alerts/', '/hawkular/alerts/'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/hawkular/alerts/', '/hawkular/alerts'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/hawkular/alerts/', 'hawkular/alerts/'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/hawkular/alerts/', 'hawkular/alerts'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://127.0.0.1/hawkular/alerts/', 'hawkular/alerts'
    expect(ret).to eq('http://127.0.0.1/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'https://127.0.0.1/hawkular/alerts/', 'hawkular/alerts'
    expect(ret).to eq('https://127.0.0.1/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'https://localhost:8080/', 'hawkular/alerts'
    expect(ret).to eq('https://localhost:8080/hawkular/alerts')

    expect { c.normalize_entrypoint_url 'https://localhost:8080/hawkular/alerts', '' }
      .to raise_error(Hawkular::ArgumentError)

    uri = URI.parse 'https://localhost:8080/'
    ret = c.normalize_entrypoint_url uri, 'hawkular/alerts'
    expect(ret).to eq('https://localhost:8080/hawkular/alerts')

    uri = URI.parse 'http://localhost:8080/hawkular/alerts/'
    ret = c.normalize_entrypoint_url uri, '/hawkular/alerts/'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')
  end

  it 'Should change http to ws and https to wss on different types of urls' do
    c = Hawkular::BaseClient.new('not-needed-for-this-test')
    ret = c.url_with_websocket_scheme 'http://localhost:8080'
    expect(ret).to eq('ws://localhost:8080')

    ret = c.url_with_websocket_scheme 'https://localhost:8443'
    expect(ret).to eq('wss://localhost:8443')

    ret = c.url_with_websocket_scheme 'http://localhost'
    expect(ret).to eq('ws://localhost')

    ret = c.url_with_websocket_scheme 'https://localhost'
    expect(ret).to eq('wss://localhost')

    ret = c.url_with_websocket_scheme 'http://localhost:8080/hawkular/inventory/'
    expect(ret).to eq('ws://localhost:8080/hawkular/inventory/')

    ret = c.url_with_websocket_scheme 'https://localhost:8443/hawkular/inventory/'
    expect(ret).to eq('wss://localhost:8443/hawkular/inventory/')

    ret = c.url_with_websocket_scheme 'http://localhost/hawkular/inventory/'
    expect(ret).to eq('ws://localhost/hawkular/inventory/')

    ret = c.url_with_websocket_scheme 'https://localhost/hawkular/inventory/'
    expect(ret).to eq('wss://localhost/hawkular/inventory/')

    ret = c.url_with_websocket_scheme 'http://localhost:8080/http'
    expect(ret).to eq('ws://localhost:8080/http')

    ret = c.url_with_websocket_scheme 'https://localhost:8443/http/https'
    expect(ret).to eq('wss://localhost:8443/http/https')

    ret = c.url_with_websocket_scheme 'ftp://http:8080'
    expect(ret).to eq('ftp://http:8080')

    ret = c.url_with_websocket_scheme 'ftp://https'
    expect(ret).to eq('ftp://https')

    uri = URI.parse 'http://localhost:8080/hawkular/inventory'
    ret = c.url_with_websocket_scheme uri
    expect(ret).to eq('ws://localhost:8080/hawkular/inventory')

    uri = URI.parse 'https://localhost:8443/hawkular/inventory'
    ret = c.url_with_websocket_scheme uri
    expect(ret).to eq('wss://localhost:8443/hawkular/inventory')
  end

  it 'Should throw a HawkularConnectionException when host not listening to port' do
    begin
      WebMock.disable!
      VCR.turned_off do
        c = Hawkular::BaseClient.new('127.0.0.1:0')
        expect do
          c.http_get('not-needed-for-this-test')
        end.to raise_error(Hawkular::BaseClient::HawkularConnectionException)
      end
    ensure
      WebMock.enable!
    end
  end

  it 'Should throw a HawkularConnectionException when unknown host' do
    begin
      WebMock.disable!
      VCR.turned_off do
        c = Hawkular::BaseClient.new('some-unknown-and-random-host-that-wont-exist')
        expect do
          c.http_get('not-needed-for-this-test')
        end.to raise_error(Hawkular::BaseClient::HawkularConnectionException)
      end
    ensure
      WebMock.enable!
    end
  end
end

describe 'Url builder' do
  it 'Should encode simple url' do
    expect(Hawkular::BaseClient.new('not-needed').url('resource/endpoint')).to eql('resource/endpoint')
  end

  it 'Should encode with one param' do
    expect(Hawkular::BaseClient.new('not-needed').url('resource/%s', 5)).to eql('resource/5')
  end

  it 'Should work with booleans' do
    expect(Hawkular::BaseClient.new('not-needed').url('resource/%s', true)).to eql('resource/true')
  end

  it 'Should work with symbols' do
    expect(Hawkular::BaseClient.new('not-needed')
      .url('abc/%s', :true)).to eql('abc/true') # rubocop:disable Lint/BooleanSymbol
  end

  it 'Should work with multiple params' do
    expect(Hawkular::BaseClient.new('not-needed')
      .url('resource/%s/inner/%s', true, :ok)).to eql('resource/true/inner/ok')
  end

  it 'Should work with & and ? params' do
    expect(Hawkular::BaseClient.new('not-needed')
    .url('resource/%s/stuff?myid=%s&this=that', 'super', '0&delete_everything=true'))
      .to eql('resource/super/stuff?myid=0%26delete_everything%3Dtrue&this=that')
  end
end
