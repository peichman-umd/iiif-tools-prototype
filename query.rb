#!/usr/bin/env ruby

require 'faraday'
require 'faraday_middleware'

# on local connections, we use self-signed certificates
# so we want to skip peer verification
require 'openssl'
OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE

solr_host = 'solrlocal:8984'

solr_conn = Faraday.new(:url => "https://#{solr_host}") do |faraday|
  # parse all responses as JSON, since Solr returns JSON as "text/plain"
  #faraday.response :json
  faraday.adapter  Faraday.default_adapter
end


params = {
  'q'                   => "ocr_text:#{ARGV[0]}",
  'wt'                  => 'json',
  'fl'                  => 'id',
  'indent'              => 'true',
  'hl'                  => 'true',
  'hl.fl'               => 'ocr_text',
  'hl.simple.pre'       => '<em>',
  'hl.simple.post'      => '</em>',
  'hl.fragsize'         => 0,
  'hl.maxAnalyzedChars' => 100000,
}

solr_response = solr_conn.get '/solr/fedora4/select', params

print solr_response.body
