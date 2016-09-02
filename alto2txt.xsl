<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet 
  xmlns:alto="http://www.loc.gov/standards/alto/ns-v2#"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">

  <xsl:output method="text" indent="no"/>
  <xsl:strip-space elements="*"/>

  <xsl:param name="resolution">400</xsl:param>

  <xsl:variable name="measurementUnit">
    <xsl:choose>
      <xsl:when test="alto:alto/alto:Description/alto:MeasurementUnit = 'inch1200'">1200</xsl:when>
      <xsl:otherwise>
        <xsl:message terminate="yes">Unsupported measurement unit</xsl:message>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:variable>

  <xsl:template match="/">
    <xsl:apply-templates select="//alto:TextBlock"/>
  </xsl:template>

  <xsl:template match="alto:String">
    <xsl:choose>
      <xsl:when test="@SUBS_TYPE = 'HypPart1'">
        <xsl:value-of select="@SUBS_CONTENT"/>
        <xsl:call-template name="coordinates"/>
      </xsl:when>
      <xsl:when test="@SUBS_TYPE = 'HypPart2'">
        <!-- TODO: include the coordinates of the second part of a hyphenated word -->
      </xsl:when>
      <xsl:otherwise>
        <xsl:value-of select="@CONTENT"/>
        <xsl:call-template name="coordinates"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <xsl:template match="alto:SP">
    <xsl:text> </xsl:text>
  </xsl:template>

  <xsl:template match="alto:TextLine">
    <xsl:apply-templates/>
    <xsl:text>&#x0a;</xsl:text>
  </xsl:template>

  <xsl:template match="alto:TextBlock">
    <xsl:apply-templates/>
    <xsl:text>&#x0a;</xsl:text>
  </xsl:template>

  <xsl:template name="coordinates">
    <xsl:text>{</xsl:text>
    <xsl:call-template name="scale"><xsl:with-param name="value" select="@HPOS"/></xsl:call-template>
    <xsl:text>,</xsl:text>
    <xsl:call-template name="scale"><xsl:with-param name="value" select="@VPOS"/></xsl:call-template>
    <xsl:text>,</xsl:text>
    <xsl:call-template name="scale"><xsl:with-param name="value" select="@WIDTH"/></xsl:call-template>
    <xsl:text>,</xsl:text>
    <xsl:call-template name="scale"><xsl:with-param name="value" select="@HEIGHT"/></xsl:call-template>
    <xsl:text>}</xsl:text>
  </xsl:template>

  <xsl:template name="scale">
    <xsl:param name="value"/>
    <xsl:value-of select="round($value * $resolution div $measurementUnit)"/>
  </xsl:template>


</xsl:stylesheet>
