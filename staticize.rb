require 'open-uri'

require 'dotenv'
require 'aws-sdk'
require 'nokogiri'
require 'addressable/uri'

require './util' # remove_query, remove_fragment, convert_site_url, calc_s3object_key, extract_urls_from_css


Dotenv.load


source_site_url = ENV['SOURCE_SITE_URL']
target_site_url = ENV['TARGET_SITE_URL']
cdn_site_url = ENV['CDN_SITE_URL']

output_dir_html  ="#{ENV['PATH_OUTPUT_DIR']}/html"
output_dir_cdn   ="#{ENV['PATH_OUTPUT_DIR']}/cdn"


source_site_url = source_site_url[0..-2] if source_site_url.end_with?('/')
target_site_url = target_site_url[0..-2] if target_site_url.end_with?('/')
cdn_site_url =    cdn_site_url[0..-2]    if cdn_site_url.end_with?('/')


uncrawled_urls = [source_site_url + '/']
crawled_urls = {source_site_url => true}
static_file_urls = []
css_urls_gathered = []
s3objects = []



while uncrawled_urls.length > 0 do

  crawling_url = uncrawled_urls.shift
  crawled_urls[crawling_url] = true

  puts 'Crawling ' + crawling_url

  parsed_crawling_url = Addressable::URI.parse crawling_url

  response = open parsed_crawling_url

  if response.content_type.nil?
    next
  elsif response.content_type.start_with?('text/html')
    nokogiried = Nokogiri::HTML(response.read)

    ahref_nodes      = nokogiried.xpath("//a                       /@href").select{ |node| parsed_crawling_url.join(node.value).to_s.start_with?(source_site_url) }
    javascript_nodes = nokogiried.xpath("//script                  /@src") .select{ |node| parsed_crawling_url.join(node.value).to_s.start_with?(source_site_url) }
    image_nodes      = nokogiried.xpath("//img                     /@src") .select{ |node| parsed_crawling_url.join(node.value).to_s.start_with?(source_site_url) }
    css_nodes        = nokogiried.xpath("//link[@rel='stylesheet'] /@href").select{ |node| parsed_crawling_url.join(node.value).to_s.start_with?(source_site_url) }
    prefetch_nodes   = nokogiried.xpath("//link[@rel='sz-prefetch']/@href").select{ |node| parsed_crawling_url.join(node.value).to_s.start_with?(source_site_url) }
    base_nodes       = nokogiried.xpath("//base                    /@href").select{ |node| parsed_crawling_url.join(node.value).to_s.start_with?(source_site_url) }

    if base_nodes.size > 0
      base_url = Addressable::URI.parse(base_nodes[-1].value)
    else
      base_url = parsed_crawling_url
    end

    ahref_urls      = ahref_nodes     .map{ |node| base_url.join(node.value).to_s }
    javascript_urls = javascript_nodes.map{ |node| base_url.join(node.value).to_s }
    css_urls        = css_nodes       .map{ |node| base_url.join(node.value).to_s }
    image_urls      = image_nodes     .map{ |node| base_url.join(node.value).to_s }
    prefetch_urls   = prefetch_nodes  .map{ |node| base_url.join(node.value).to_s }

    new_uncrawled_urls = ahref_urls.map{ |url| remove_fragment(url) }.reject{ |url| crawled_urls[url] }
    uncrawled_urls.concat(new_uncrawled_urls).uniq!

    static_file_urls.concat(javascript_urls + image_urls + prefetch_urls).uniq!
    css_urls_gathered.concat(css_urls).uniq!

    ahref_nodes.each do |node|
      node.value = remove_query(convert_site_url(source_site_url, target_site_url, base_url.join(node.value).to_s))
    end

    (javascript_nodes + image_nodes + css_nodes + prefetch_nodes + base_nodes).each do |node|
      node.value = remove_query(convert_site_url(source_site_url, cdn_site_url, base_url.join(node.value).to_s))
    end

    s3objects << { key: calc_s3object_key(source_site_url, remove_query(crawling_url)), body: nokogiried.to_html }
  else
    s3objects << { key: calc_s3object_key(source_site_url, remove_query(crawling_url)), body: response.read }
  end
end


css_file_objects = css_urls_gathered.map.with_index(1) { |url, index|

  puts 'Crawling ' + url
  parsed_url = Addressable::URI.parse url

  css_content = open(Addressable::URI.parse(url)).read
  urls_in_css = extract_urls_from_css(css_content).map{ |url| parsed_url.join(url).to_s }.select{ |url| url.start_with?(source_site_url) }

  static_file_urls.concat(urls_in_css).uniq!

  { key: calc_s3object_key(source_site_url, remove_query(url)), body: css_content }
}

static_file_objects = static_file_urls.map.with_index(1){ |url, index|

  puts "Downloading(#{index}/#{static_file_urls.size}) #{url}"
  { key: calc_s3object_key(source_site_url, remove_query(url)), body: open(Addressable::URI.parse(url)).read }
}


Aws.use_bundled_cert!
Aws.config.update({access_key_id: ENV['AWS_ACCESS_KEY_ID'], secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'], region: ENV['AWS_REGION']})
s3 = Aws::S3::Resource.new
bucket = s3.bucket(ENV['AWS_S3_BUCKET'])

num_objects = s3objects.size + static_file_objects.size + css_file_objects.size

s3objects.each.with_index(1) do |s3object, index|
  if s3object[:key] == ""
    FileUtils.mkdir_p("#{output_dir_html}") unless FileTest.exist?("#{output_dir_html}")
    puts "Generating(#{index}/#{num_objects}) #{output_dir_html}/index.html"
    File.open("#{output_dir_html}/index.html", "w") { |f| f.puts(s3object[:body]) }
    #bucket.object("index.html").put(body: s3object[:body])
  else
    _path_save_dir  ="#{output_dir_html}/#{File.dirname(s3object[:key])}"
    FileUtils.mkdir_p("#{_path_save_dir}") unless FileTest.exist?("#{_path_save_dir}")
    puts "Generating(#{index}/#{num_objects}) #{output_dir_html}/#{s3object[:key]}"
    File.open("#{output_dir_html}/#{s3object[:key]}", "w") { |f| f.puts(s3object[:body]) }
    #bucket.object(s3object[:key]).put(body: s3object[:body])
  end
end


Aws.config.update({access_key_id: ENV['CDN_AWS_ACCESS_KEY_ID'], secret_access_key: ENV['CDN_AWS_SECRET_ACCESS_KEY'], region: ENV['CDN_AWS_REGION']})
bucket = s3.bucket(ENV['CDN_AWS_S3_BUCKET'])
static_file_objects.each.with_index(1) do |static_file_object, index|
  _path_save_dir  ="#{output_dir_cdn}/#{File.dirname(static_file_object[:key])}"
  FileUtils.mkdir_p("#{_path_save_dir}") unless FileTest.exist?("#{_path_save_dir}")
  puts "Generating(#{index + s3objects.size}/#{num_objects}) #{output_dir_cdn}/#{static_file_object[:key]}"
  File.open("#{output_dir_cdn}/#{static_file_object[:key]}", "wb") { |f| f.puts(static_file_object[:body]) }
  #bucket.object(static_file_object[:key]).put(body: static_file_object[:body])
end


css_file_objects.each.with_index(1) do |css_file_object, index|
  _path_save_dir  ="#{output_dir_cdn}/#{File.dirname(css_file_object[:key])}"
  FileUtils.mkdir_p("#{_path_save_dir}") unless FileTest.exist?("#{_path_save_dir}")
  puts "Generating(#{index + s3objects.size + static_file_objects.size}/#{num_objects}) #{output_dir_cdn}/#{css_file_object[:key]}"
  File.open("#{output_dir_cdn}/#{css_file_object[:key]}", "wb") { |f| f.puts(css_file_object[:body]) }
  #bucket.object(css_file_object[:key]).put(body: css_file_object[:body])
end
