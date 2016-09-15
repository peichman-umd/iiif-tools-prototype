#!/usr/bin/env ruby

require './alto.rb'
require 'nokogiri'
require 'json'
require 'rmagick'

nsmap = {
  'mets'  => 'http://www.loc.gov/METS/',
  'xlink' => 'http://www.w3.org/1999/xlink',
}

# basepath should be the path to the directory holding the issue files
# the article-level METS file path will be calculated from it
basepath = ARGV[0]
lccn, reel, issue = basepath.match(/(\w+)\/(\d+)\/(\d+)\/?$/).captures
filename = File.expand_path("../../../Article-Level/#{lccn}/#{reel}/#{issue}/#{issue}.xml", basepath)

# article to extract
article_number = (ARGV[1] || 1).to_i

mets_xmldoc = Nokogiri::XML(File.open(filename))
mets = mets_xmldoc.xpath('/mets:mets', nsmap).first

file_for = {}

# read filemap
mets.xpath('mets:fileSec//mets:file[@USE="ocr"]', nsmap).each do |file|
  id = file.xpath('@ID').first.to_s
  path = file.xpath('mets:FLocat/@xlink:href', nsmap).first.to_s
  target_file = File.expand_path(path, basepath)
  file_for[id] = {
    id: id,
    group: file.xpath('../@ID', nsmap).first.to_s,
    path: target_file,
  }
  if file.xpath('@USE').first.to_s == 'ocr'
    xmldoc = Nokogiri::XML(File.open(target_file))

    # get master file
    master_file = file.xpath('../mets:file[@USE="master"]', nsmap).first
    master_file_href = master_file.xpath('mets:FLocat/@xlink:href', nsmap).first.to_s
    master_file_path = File.expand_path(master_file_href, basepath)

    # get resolution to calculate pixel coordinates
    image = Magick::ImageList.new(master_file_path)

    file_for[id][:ocr] = OCRResource.new(xmldoc, image)
  end
end

articles = []

# find articles
mets.xpath('mets:structMap//mets:div[@TYPE="article"]', nsmap).each do |article|
  annotations = []
  label = article.attribute('LABEL').value
  struct_id = article.attribute('ID').value
  article.xpath('.//mets:area', nsmap).each do |area|
    fileid  = area.attribute('FILEID').value
    blockid = area.attribute('BEGIN').value

    file = file_for[fileid]
    ocr = file[:ocr]

    block = ocr.textblock(blockid)

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
        #TODO: canvas URI for the page that this appears on
        "full" => file[:group],
      },
      "motivation" => "oa:highlighting"
    })

  end
  articles.push({
    label: label,
    annotations: annotations,
  })
end

article = articles[article_number - 1]
abort("No article #{article_number}") if article == nil

#TODO: get base URI of the issue/manifest URI (get UUID from Fedora object?)
annotation_list = {
  "@context"  => "http://iiif.io/api/presentation/2/context.json",
  "@id"       => "annotations/article#{article_number - 1}",
  "@type"     => "sc:AnnotationList",
  "label"     => article[:label],
  "resources" => article[:annotations],
}
print JSON.dump(annotation_list)
