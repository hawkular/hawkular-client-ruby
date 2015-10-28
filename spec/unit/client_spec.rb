require "#{File.dirname(__FILE__)}/../spec_helper"

describe Hawkular::Metrics::Client do
  context "client initialization" do
    it "should accept no option" do
      credentials = { username: 'mockuser', password: 'mockpass' }
      Hawkular::Metrics::Client::new("http://localhost:8080/hawkular/metrics", credentials)
    end

    it "should support no parameters" do
      Hawkular::Metrics::Client::new()
    end

    it "should accept Hawkular-Tenant option" do
      credentials = { username: 'mockuser', password: 'mockpass' }
      @client = Hawkular::Metrics::Client::new("http://localhost:8080/hawkular/metrics", credentials, tenant: "foo")
      headers = @client.send(:http_headers)
      expect(headers[:"Hawkular-Tenant"]).to eql("foo")
    end

    it "should define subcomponents" do
      client = Hawkular::Metrics::Client::new()
      expect(client.tenants).not_to be nil
      expect(client.counters).not_to be nil
      expect(client.gauges).not_to be nil
    end

  end

  context "http comms" do
    before(:each) do
      credentials = { username: 'mockuser', password: 'mockpass' }
      @client = Hawkular::Metrics::Client::new("http://localhost:8080/hawkular/metrics", credentials)
    end

    it "should add Accept: headers" do
      headers = @client.send(:http_headers)
      expect(headers[:accept]).to eql("application/json")
    end

    it "should keep existing Accept: headers" do
      value = "application/json; foo=bar;"
      headers = @client.send(:http_headers, {:accept => value})
      expect(headers[:accept]).to eql(value)
    end
  end
end
