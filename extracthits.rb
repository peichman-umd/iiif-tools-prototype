#!/usr/bin/env ruby

require "json"

ocr_field = 'ocr_text'
annotations = []
results = JSON.parse($stdin.read)

results["highlighting"].each do |uri, fields|
  if fields[ocr_field] then
    fields[ocr_field].each do |text|
      count = 0
      text.scan(/<em>([^<]*)<\/em>{(\d+,\d+,\d+,\d+)}/) do |hit, coords|
        count += 1
        annotations.push({
          "@id" => "search-result-%03d" % count,
          "@type" => ["oa:Annotation", "umd:searchResult"],
          "resource" => [ {
            "@type" => "dctypes:Text",
            "chars"=> hit
          } ],
          "on" => {
            "@type" => "oa:SpecificResource",
            "selector" => {
              "@type" => "oa:FragmentSelector",
              "value" => "xywh=#{coords}"
            },
            "full" => "http://iiif-sandbox.lib.umd.edu/manifests/sn83045081/1902-01-15/1"
          },
          "motivation" => "oa:highlighting"
        })
      end
    end
  end
end

annotation_list = {
  "@context"  => "http://iiif.io/api/presentation/2/context.json",
  "@id"       => "http://iiif-sandbox.lib.umd.edu/manifests/sn83045081/1902-01-15/1-dynamic",
  "@type"     => "sc:AnnotationList",
  "resources" => annotations
}
print JSON.dump(annotation_list)
