#!/usr/bin/env ruby

require 'faraday'
require 'faraday_middleware'
require 'json'
require 'nokogiri'
require './alto.rb'
require 'openssl'

class ImageStub
  def initialize(x_resolution, y_resolution)
    @x_resolution = x_resolution
    @y_resolution = y_resolution
  end
  def x_resolution
    @x_resolution
  end
  def y_resolution
    @y_resolution
  end
end

nsmap = {
  'mets'  => 'http://www.loc.gov/METS/',
  'xlink' => 'http://www.w3.org/1999/xlink',
  'mix'   => 'http://www.loc.gov/mix/',
}

property = { solr_host: 'solrlocal:8984' }

solr_conn = Faraday.new(:url => "https://#{property[:solr_host]}", ssl: { verify: false }) do |faraday|
  # parse all responses as JSON, since Solr returns JSON as "text/plain"
  faraday.response :json
  faraday.adapter  Faraday.default_adapter
end

issue_uri = 'https://fcrepolocal/fcrepo/rest/pcdm/55/e2/be/6e/55e2be6e-68d5-4f61-8781-f6fa8931bbd7'
solr_response = solr_conn.get '/solr/fedora4/select',
  'q' => "id:#{issue_uri.gsub(':', '\:')}",
  'fl' => '*,mets:[subquery],articles:[subquery],p:[subquery]',
  'mets.q' => '{!terms f=id v=$row.pcdm_related_objects}',
  'mets.fq' => 'title:"METS metadata"',
  'mets.fl' => 'id,title,pcdm_files',
  'articles.q' => '{!terms f=id v=$row.pcdm_members}',
  'articles.fq' => 'rdf_type:bibo\:Article',
  'articles.fl' => 'id,title',
  'articles.rows' => 1000,
  'p.q' => '{!terms f=id v=$row.pcdm_members}',
  'p.fq' => 'rdf_type:ndnp\:Page',
  'p.fl' => 'id,title,page_number,ocr:[subquery],master:[subquery]',
  'p.ocr.q' => '{!terms f=id v=$row.pcdm_files}',
  'p.ocr.fq' => 'rdf_type:pcdmuse\:ExtractedText',
  'p.ocr.fl' => 'id,title',
  'p.master.q' => '{!terms f=id v=$row.pcdm_files}',
  'p.master.fq' => 'rdf_type:pcdmuse\:PreservationMasterFile',
  'p.master.fl' => 'id,title,image_height,image_width',
  'wt' => 'json'
document = solr_response.body['response']['docs'][0]
#puts JSON.dump(document)
#exit

conn = Faraday.new(ssl: { verify: false })

article_xml_uri = document['mets']['docs'].select{|doc| doc['title'][0] =~ /article METS metadata/ }[0]['pcdm_files'][0]
issue_xml_uri = document['mets']['docs'].select{|doc| doc['title'][0] =~ /issue METS metadata/ }[0]['pcdm_files'][0]

issue_xmldoc = Nokogiri::XML(conn.get(issue_xml_uri).body)
issue_mets = issue_xmldoc.xpath('/mets:mets', nsmap).first

article_resources = document['articles']['docs'].clone
#puts JSON.dump(article_resources)
#exit

page_resources = {}
pages = document['p']['docs']
pages.map do |page|
  pagenum = page['page_number']
  image_metrics = issue_mets.xpath("mets:amdSec/mets:techMD[@ID='mixmasterFile#{pagenum}']//mix:SpatialMetrics", nsmap).first
  x_res = image_metrics.xpath('mix:XSamplingFrequency', nsmap).first.text.to_i
  y_res = image_metrics.xpath('mix:YSamplingFrequency', nsmap).first.text.to_i
  ocr_uri = page['ocr'][0]['id']
  ocr_xmldoc = Nokogiri::XML(conn.get(ocr_uri).body)
  ocr_resource = OCRResource.new(ocr_xmldoc, ImageStub.new(x_res, y_res))
  page_resources["ocrFile#{pagenum}"] = {
    pagenum: pagenum,
    id: page['id'],
    ocrfile: ocr_uri,
    ocr: ocr_resource,
    masterfile: page['master'][0]['id'],
    image_width: page['master'][0]['image_width'],
    image_height: page['master'][0]['image_height'],
  }
end

#puts JSON.dump(page_resources)
#exit
#puts article_xml_uri
#puts issue_xml_uri

fcrepo_update_conn = Faraday.new(
  ssl: {
    verify: false,
    client_cert: OpenSSL::X509::Certificate.new(File.open('/Users/peichman/batchload/fcrepolocal/batchloader.pem', 'r')),
    client_key: OpenSSL::PKey::RSA.new(File.open('/Users/peichman/batchload/fcrepolocal/batchloader.key', 'r')),
  }
)

article_annotations = []
res = conn.get(article_xml_uri)
article_xmldoc = Nokogiri::XML(res.body)
article_mets = article_xmldoc.xpath('/mets:mets', nsmap).first
article_mets.xpath('mets:structMap//mets:div[@TYPE="article"]', nsmap).each do |article|
  article_title = article.attribute('LABEL').value
  i = article_resources.find_index {|v| v['title'][0] == article_title }
  if i
    article_resource = article_resources.delete_at(i)
    article_uri = article_resource['id']
    article_pages = []
    article_text = ''
    article_tagged_text = ''
    annotations = []
    article.xpath('.//mets:area', nsmap).each do |area|
      fileid  = area.attribute('FILEID').value
      blockid = area.attribute('BEGIN').value
      page = page_resources[fileid]
      ocr = page[:ocr]
      block = ocr.textblock(blockid)
      article_text += block.text
      article_tagged_text += block.tagged_text(ocr)
      article_pages.push(page[:pagenum])

      annotations.push({
        "@id" => "#{fileid}-#{block.id}",
        "@type" => ["oa:Annotation", "umd:Article"],
        "resource" => [
          {
            "@type" => "cnt:ContentAsText",
            "format" => "text/plain",
            "chars" => block.text,
          },
        ],
        "on" => {
          "@type" => "oa:SpecificResource",
          "selector" => {
            "@type" => "oa:FragmentSelector",
            "value" => "xywh=#{ocr.coordinates(block)}",
          },
          "full" => page[:id],
        },
        "motivation" => "oa:highlighting"
      })
    end
    article_annotations.push({
      label: article_title,
      annotations: annotations,
    })

    article_pages.uniq!.sort!
    #puts article_title
    #puts article_tagged_text
    #puts
    solr_response = solr_conn.get

    solr_response = solr_conn.post do |req|
      req.url '/solr/fedora4/update'
      req.headers['Content-Type'] = 'application/json'
      req.body = JSON.dump({
        'add' => {
          'doc' => {
            'id' => article_uri,
            'ocr_text' => { 'set' => article_text },
            'ocr_text_tagged' => { 'set' => article_tagged_text },
          },
        },
        'commit' => {},
      })

      sparql_update = <<END
PREFIX bibo: <http://purl.org/ontology/bibo/>

INSERT DATA {
  <> bibo:content """#{article_text}""" ;
    bibo:pageStart #{article_pages.first} ;
    bibo:pageEnd #{article_pages.last} .
}
END
      fcrepo_res = fcrepo_update_conn.patch do |req|
        req.url article_uri
        req.headers['Content-Type'] = 'application/sparql-update'
        req.body = sparql_update
      end
    end
  else
    #puts "No article URI with title matching #{article_title}"
  end
end

puts JSON.dump(article_annotations)
