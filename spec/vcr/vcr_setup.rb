require 'vcr'
require 'webmock'

VCR.configure do |c|
  c.cassette_library_dir = 'spec/vcr_cassettes'
  c.hook_into :webmock
  c.default_cassette_options = { match_requests_on:  [:uri, :method] }
  c.debug_logger = File.open('spec/vcr.log', 'w')
  c.configure_rspec_metadata!
end
