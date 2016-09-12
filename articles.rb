#!/usr/bin/env ruby

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
    file_for[id][:master] = File.expand_path(master_file_href, basepath)

    # get resolution to calculate pixel coordinates
    image = Magick::ImageList.new(file_for[id][:master])

    # get measurement unit scale factor
    # see https://www.loc.gov/standards/alto/description.html
    unit = xmldoc.xpath('/xmlns:alto/xmlns:Description/xmlns:MeasurementUnit/text()').first.to_s
    xres = image.x_resolution
    yres = image.y_resolution

    if unit == 'inch1200'
      file_for[id][:xscale] = xres / 1200.0
      file_for[id][:yscale] = yres / 1200.0
    elsif unit == 'mm10'
      file_for[id][:xscale] = xres / 254.0
      file_for[id][:yscale] = yres / 254.0
    elsif unit == 'pixel'
      file_for[id][:xscale] = 1
      file_for[id][:yscale] = 1
    elsif
      abort("Unknown MeasurementUnit #{unit}")
    end

    file_for[id][:xmldoc] = xmldoc
  end
end

articles = []

# find articles
mets.xpath('mets:structMap//mets:div[@TYPE="article"]', nsmap).each do |article|
  annotations = []
  label = article.xpath('@LABEL').first.to_s
  struct_id = article.xpath('@ID').first.to_s
  article.xpath('.//mets:area', nsmap).each do |area|
    fileid = area.xpath('@FILEID').first.to_s
    blockid = area.xpath('@BEGIN').first.to_s

    file = file_for[fileid]

    block = file[:xmldoc].xpath("//xmlns:TextBlock[@ID='#{blockid}']").first

    hpos   = block.xpath('@HPOS').first.to_s.to_i
    vpos   = block.xpath('@VPOS').first.to_s.to_i
    width  = block.xpath('@WIDTH').first.to_s.to_i
    height = block.xpath('@HEIGHT').first.to_s.to_i

    scale = file[:scale]

    x = (hpos   * file[:xscale]).round
    y = (vpos   * file[:yscale]).round
    w = (width  * file[:xscale]).round
    h = (height * file[:yscale]).round
    coords = [x,y,w,h].join(',')

    annotations.push({
      "@id" => "#{fileid}-#{blockid}",
      "@type" => ["oa:Annotation", "umd:Article"],
      "resource" => [],
      "on" => {
        "@type" => "oa:SpecificResource",
        "selector" => {
          "@type" => "oa:FragmentSelector",
          "value" => "xywh=#{coords}",
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
