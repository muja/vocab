#!/usr/bin/env ruby

require 'pathname'
require 'csv'
require 'json'
require 'hashie'

Dir.chdir Pathname.new(__FILE__).parent
Dir.mkdir "out" unless Dir.exist? "out"

FILE_TEMPLATE = Pathname.new(Dir.pwd).parent.join("kanjivg", "kanji", "0%s.svg").to_s

def extract(node)
  kanji = node.css("literal").text
  on = node.css("reading[r_type=ja_on]").map(&:text).join(" ")
  kun = node.css("reading[r_type=ja_kun]").map(&:text).join(" ")
  meaning = node.css("meaning:not([m_lang])").map(&:text).join(", ")
  Hashie::Mash.new(kanji: kanji, on: on, kun: kun, meaning: meaning)
end

characters = if File.exists? "out/kanjidata.json"
  Hashie::Mash.new(JSON.parse(File.read("out/kanjidata.json")))
else
  puts "Fetching kanji data..."
  require 'open-uri'
  require 'nokogiri'
  require 'zlib'

  # FOR LICENSE see http://www.csse.monash.edu.au/~jwb/kanjidic2/
  xml = open("http://www.csse.monash.edu.au/~jwb/kanjidic2/kanjidic2.xml.gz")
  characters = Nokogiri::XML(Zlib::GzipReader.new(xml)).css('character')
  i = 0
  characters.inject({}) do |h, char|
    print "\r"
    print i += 1
    info = extract(char)
    h.merge info.kanji => info
  end.tap do |characters|
    puts
    license = open("http://www.edrdg.org/edrdg/licence.html").read
    File.write("out/kanjidata.license.html", license)

    File.write("out/kanjidata.json", JSON.pretty_generate(characters))
  end
end

by_file = {}
all = Dir["in/**/*"].map do |file|
  next [] unless File.exists?(file)
  lecture = File.read(file).strip
  by_file[file] = CSV.parse(lecture, col_sep: ";").map do |kanji, meaning, on, kun|
    if char = characters[kanji]
      on = char.on
      kun = char.kun
      meaning_en = char.meaning
    else
      puts "#{kanji}: Not found! (in #{file}), on: #{on}, kun: #{kun}"
      on ||= ""
      kun ||= ""
    end
    Hashie::Mash.new(
      kanji: kanji,
      on: on.split.join("; "),
      kun: kun.split.map do |kun|
        real, additional = kun.split(".")
        additional ? "<u>#{real}</u>#{additional}" : kun
      end.join("; "),
      meaning_de: meaning,
      meaning_en: meaning_en,
      svg: FILE_TEMPLATE % kanji.ord.to_s(16),
    )
  end
end.flatten

by_file.merge("all" => all).each do |infile, vocabs|
  csv = CSV.generate(col_sep: ";") do |csv|
    vocabs.each do |vocab|
      csv << vocab.values
    end
  end
  out = File.basename(infile, File.extname(infile))
  File.write "out/#{out}.csv", csv
end
