# TARO-ead-exporter

An ArchivesSpace EAD export plugin for Texas Archival Resources Online.

This plugin modifies the staff-side EAD exporter to produce EAD files compatible with the Texas Archival Resources Online project. It also include an updated XSL file for staff PDF generation.

It has been updated to be compatible with ASpace 4.1.1

## Installation

* Download the file from https://github.com/lyrasis/TARO-ead-exporter/releases
* Unzip the file and copy it to your ASpace plugins directory
* Rename the directory from TARO-ead-exporter-vX.X to TARO-ead-exporter
* Add 'TARO-ead-exporter' to the AppConfig[:plugins] list in your config.rb
* Copy the as-ead-pdf.xsl file to your ASpace stylesheets directory
