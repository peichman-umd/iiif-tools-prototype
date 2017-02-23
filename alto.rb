class OCRResource
  def initialize(xmldoc, image)
    @xmldoc = xmldoc

    # get measurement unit scale factor
    # see https://www.loc.gov/standards/alto/description.html
    unit = xmldoc.xpath('/xmlns:alto/xmlns:Description/xmlns:MeasurementUnit/text()').first.to_s
    xres = image.x_resolution
    yres = image.y_resolution

    if unit == 'inch1200'
      @xscale = xres / 1200.0
      @yscale = yres / 1200.0
    elsif unit == 'mm10'
      @xscale = xres / 254.0
      @yscale = yres / 254.0
    elsif unit == 'pixel'
      @xscale = 1
      @yscale = 1
    elsif
      abort("Unknown MeasurementUnit #{unit}")
    end
  end

  def xscale
    @xscale
  end

  def yscale
    @yscale
  end

  def textblock(id)
    TextBlock.new(@xmldoc.xpath("//xmlns:TextBlock[@ID='#{id}']").first)
  end

  def textlines
    @xmldoc.xpath('//xmlns:TextLine').map { |node| TextLine.new(node) }
  end

  def coordinates(region)
    region.coordinates(@xscale, @yscale)
  end
end

class Region
  def initialize(element)
    @element = element
  end

  def id
    @element.attribute('ID').value
  end

  def hpos
    @element.attribute('HPOS').value.to_i
  end

  def vpos
    @element.attribute('VPOS').value.to_i
  end

  def width
    @element.attribute('WIDTH').value.to_i
  end

  def height
    @element.attribute('HEIGHT').value.to_i
  end

  def coordinates(xscale, yscale)
    x = (self.hpos   * xscale).round
    y = (self.vpos   * yscale).round
    w = (self.width  * xscale).round
    h = (self.height * yscale).round

    [x,y,w,h].join(',')
  end
end

class TextBlock < Region
  def element
    @element
  end

  def lines
    @element.xpath('xmlns:TextLine').map { |node| TextLine.new(node) }
  end

  def text
    text = ''
    self.lines.each do |line|
      text += line.text + "\n"
    end
    text
  end

  def tagged_text(ocr_resource)
    text = ''
    self.lines.each do |line|
      text += line.tagged_text(ocr_resource) + "\n"
    end
    text
  end
end

class TextLine < Region
  def text
    text = ''
    @element.xpath('xmlns:String|xmlns:SP|xmlns:HYP').each do |node|
      if node.name == 'SP'
        text += ' '
      else
        text += node.attribute('CONTENT').value
      end
    end
    text
  end

  def tagged_text(ocr_resource)
    text = ''
    @element.xpath('xmlns:String|xmlns:SP|xmlns:HYP').each do |node|
      if node.name == 'SP'
        text += ' '
      else
        text += node.attribute('CONTENT').value
        text += "{#{ocr_resource.coordinates(self)}}"
      end
    end
    text
  end
end
