#!/usr/bin/env ruby

require './alto.rb'
require 'nokogiri'
require 'json'
require 'rmagick'

xml_filename   = ARGV[0]
image_filename = ARGV[1]

#TODO: canvas URI for the page that this appears on
canvas_name = File.basename(xml_filename)

xmldoc = Nokogiri::XML(File.open(xml_filename))
image  = Magick::ImageList.new(image_filename)

ocr = OCRResource.new(xmldoc, image)

annotations = ocr.textlines.map do |textline|
  {
    "@id" => textline.id,
    "@type" => ["oa:Annotation", "umd:Article"],
    "resource" => [
      {
        "@type" => "cnt:ContentAsText",
        "format" => "text/plain",
        "chars" => textline.text,
      },
    ],
    "on" => {
      "@type" => "oa:SpecificResource",
      "selector" => {
        "@type" => "oa:FragmentSelector",
        "value" => "xywh=#{ocr.coordinates(textline)}",
      },
      "full" => canvas_name,
    },
    "motivation" => "sc:painting"
  }
end

#TODO: get base URI of the issue/manifest URI (get UUID from Fedora object?)
annotation_list = {
  "@context"  => "http://iiif.io/api/presentation/2/context.json",
  "@id"       => "annotations/lines",
  "@type"     => "sc:AnnotationList",
  "resources" => annotations,
}
print JSON.dump(annotation_list)
