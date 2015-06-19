require 'net/http'
require 'uri'

require 'dotenv'
require 'aws-sdk'
require 'nokogiri'

require './util' # remove_query, remove_fragment, convert_site_url, calc_s3object_key, extract_urls_from_css


Dotenv.load


source_site_url = ENV['SOURCE_SITE_URL']
target_site_url = ENV['TARGET_SITE_URL']
cdn_site_url = ENV['CDN_SITE_URL']


source_site_url = source_site_url[0..-2] if source_site_url.end_with?('/')
target_site_url = target_site_url[0..-2] if target_site_url.end_with?('/')
cdn_site_url =    cdn_site_url[0..-2]    if cdn_site_url.end_with?('/')


uncrawled_urls = [source_site_url + '/']
crawled_urls = {source_site_url => true}
static_file_urls = []
css_file_urls = []
s3objects = []


while uncrawled_urls.length > 0 do
  crawling_url = uncrawled_urls.shift
  crawled_urls[crawling_url] = true

  puts 'Crawling ' + crawling_url

  response = Net::HTTP.get_response(URI.parse(crawling_url))

  if response['content-type'].start_with?('text/html')
    nokogiried = Nokogiri::HTML(response.body)

    ahref_urls      = nokogiried.xpath("//a     [starts-with(@href, '#{source_site_url}')]                   /@href").map{ |attr| attr.value }
    javascript_urls = nokogiried.xpath("//script[starts-with(@src,  '#{source_site_url}')]                   /@src") .map{ |attr| attr.value }
    stylesheet_urls = nokogiried.xpath("//link  [starts-with(@href, '#{source_site_url}')][@rel='stylesheet']/@href").map{ |attr| attr.value }
    image_urls      = nokogiried.xpath("//img   [starts-with(@src,  '#{source_site_url}')]                   /@src") .map{ |attr| attr.value }

    new_uncrawled_urls = ahref_urls.map{ |url| remove_fragment(url) }.reject{ |url| crawled_urls[url] }
    uncrawled_urls.concat(new_uncrawled_urls).uniq!

    static_file_urls.concat(javascript_urls + image_urls).uniq!
    css_file_urls.concat(stylesheet_urls).uniq!

    nokogiried.xpath("//a[starts-with(@href, '#{source_site_url}')]/@href").each do |attr|
      attr.value = remove_query(convert_site_url(source_site_url, target_site_url, attr.value))
    end

    nokogiried.xpath("//script[starts-with(@src, '#{source_site_url}')]/@src").each do |attr|
      attr.value = remove_query(convert_site_url(source_site_url, cdn_site_url, attr.value))
    end

    nokogiried.xpath("//link[@rel='stylesheet'][starts-with(@href, '#{source_site_url}')]/@href").each do |attr|
      attr.value = remove_query(convert_site_url(source_site_url, cdn_site_url, attr.value))
    end

    nokogiried.xpath("//img[starts-with(@src, '#{source_site_url}')]/@src").each do |attr|
      attr.value = remove_query(convert_site_url(source_site_url, cdn_site_url, attr.value))
    end

    s3objects << { key: calc_s3object_key(source_site_url, remove_query(crawling_url)), body: nokogiried.to_html }
  else
    s3objects << { key: calc_s3object_key(source_site_url, remove_query(crawling_url)), body: response.body }
  end
end


css_file_objects = css_file_urls.map.with_index(1) { |url, index|
  puts 'Crawling ' + url
  parsed_url = URI.parse url

  css_content = Net::HTTP.get_response(URI.parse(url)).body
  urls_in_css = extract_urls_from_css(css_content).map{ |url| (parsed_url + url).to_s }

  static_file_urls.concat(urls_in_css).uniq!

  { key: calc_s3object_key(source_site_url, remove_query(url)), body: css_content }
}

static_file_objects = static_file_urls.map.with_index(1){ |url, index|
  puts "Downloading(#{index}/#{static_file_urls.size}) #{url}"
  { key: calc_s3object_key(source_site_url, remove_query(url)), body: Net::HTTP.get_response(URI.parse(url)).body }
}


Aws.use_bundled_cert!
s3 = Aws::S3::Resource.new
bucket = s3.bucket(ENV['AWS_S3_BUCKET'])

num_objects = s3objects.size + static_file_objects.size + css_file_objects.size

s3objects.each.with_index(1) do |s3object, index|
  if s3object[:key] == ""
    puts "Uploading(#{index}/#{num_objects}) index.html"
    bucket.object("index.html").put(body: s3object[:body])
  else
    puts "Uploading(#{index}/#{num_objects}) #{s3object[:key]}"
    bucket.object(s3object[:key]).put(body: s3object[:body])
  end
end


static_file_objects.each.with_index(1) do |static_file_object, index|
  puts "Uploading(#{index + s3objects.size}/#{num_objects}) #{static_file_object[:key]}"
  bucket.object('cdn/' + static_file_object[:key]).put(body: static_file_object[:body])
end


css_file_objects.each.with_index(1) do |css_file_object, index|
  puts "Uploading(#{index + s3objects.size + static_file_objects.size}/#{num_objects}) #{css_file_object[:key]}"
  bucket.object('cdn/' + css_file_object[:key]).put(body: css_file_object[:body])
end
