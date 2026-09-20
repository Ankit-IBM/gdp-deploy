<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="xml" indent="yes"/>

  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="/domain/devices/disk[2]">
    <xsl:copy>
      <xsl:copy-of select="@*[name() != 'device']"/>
      <xsl:attribute name="device">cdrom</xsl:attribute>
      <xsl:copy-of select="driver|source"/>
      <target dev="hdc" bus="ide"/>
      <readonly/>
      <xsl:copy-of select="node()[not(self::driver or self::source or self::target or self::readonly)]"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="/domain/devices/disk[1]">
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <xsl:copy-of select="driver|source"/>
      <target dev="sda" bus="sata"/>
      <xsl:copy-of select="node()[not(self::driver or self::source or self::target)]"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="/domain/devices/interface[@type='bridge']">
    <xsl:copy>
      <xsl:copy-of select="@*|mac|source"/>
      <virtualport type="openvswitch"/>
      <xsl:copy-of select="node()[not(self::mac or self::source or self::virtualport)]"/>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>