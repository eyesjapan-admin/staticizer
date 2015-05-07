require 'open-uri'

require 'dotenv'
require 'ruby-wpdb'
require 'aws-sdk'
require 'nokogiri'

require './util' # get_redirected_url, remove_query, convert_site_url, calc_s3object_key

Dotenv.load

if ENV['WP_CONFIG_PATH'] != ""
  WPDB.from_config(ENV['WP_CONFIG_PATH'])
else
  WPDB.init("mysql2://#{ENV['DATABASE_USER']}:#{ENV['DATABASE_PASSWORD']}@#{ENV['DATABASE_HOST']}/#{ENV['DATABASE_NAME']}")
end

source_site_url = WPDB::Option.get_option('siteurl')
target_site_url = ENV['TARGET_SITE_URL']


post_urls = WPDB::Post.all
  .select{ |post| (post.post_type == 'post' || post.post_type == 'page') && post.post_status == 'publish' }
  .map{ |post| get_redirected_url(post.guid) }
  .select{ |post_url| post_url.start_with?(source_site_url) } << "#{source_site_url}/"

post_s3objects = post_urls.map do |post_url|
  post_html = open(post_url).read
  post_nokogiried = Nokogiri::HTML(post_html)

  post_nokogiried.xpath("//a[starts-with(@href, '#{source_site_url}')]/@href").each do |attr|
    attr.value = remove_query(convert_site_url(source_site_url, target_site_url, attr.value))
  end

  post_nokogiried.xpath("//script[starts-with(@src, '#{source_site_url}')]/@src").each do |attr|
    attr.value = remove_query(convert_site_url(source_site_url, target_site_url, attr.value))
  end

  post_nokogiried.xpath("//link[@rel='stylesheet'][starts-with(@href, '#{source_site_url}')]/@href").each do |attr|
    attr.value = remove_query(convert_site_url(source_site_url, target_site_url, attr.value))
  end

  post_nokogiried.xpath("//img[starts-with(@src, '#{source_site_url}')]/@src").each do |attr|
    attr.value = remove_query(convert_site_url(source_site_url, target_site_url, attr.value))
  end

  { key: calc_s3object_key(source_site_url, post_url), body: post_nokogiried.to_html }
end


attachment_urls = WPDB::Post.all
  .select{ |post| post.post_type == 'attachment' }
  .map{ |post| get_redirected_url(post.guid) }
  .select{ |post_url| post_url.start_with?(source_site_url) }

attachment_s3objects = attachment_urls.map{ |attachment_url|
  { key: calc_s3object_key(source_site_url, remove_query(attachment_url)), body: open(attachment_url).read }
}


other_urls = post_urls.map{ |post_url|
  post_html = open(post_url).read
  post_nokogiried = Nokogiri::HTML(post_html)

  javascript_urls = post_nokogiried.xpath("//script[starts-with(@src,  '#{source_site_url}')]                   /@src") .map{ |attr| attr.value }
  stylesheet_urls = post_nokogiried.xpath("//link  [starts-with(@href, '#{source_site_url}')][@rel='stylesheet']/@href").map{ |attr| attr.value }
  image_urls      = post_nokogiried.xpath("//img   [starts-with(@src,  '#{source_site_url}')]                   /@src") .map{ |attr| attr.value }

  javascript_urls + stylesheet_urls + image_urls
}.flatten(1).uniq

other_s3objects = other_urls.map{ |other_url|
  { key: calc_s3object_key(source_site_url, remove_query(other_url)), body: open(other_url).read }
}


s3objects = post_s3objects + attachment_s3objects + other_s3objects


s3 = Aws::S3::Resource.new
bucket = s3.bucket(ENV['AWS_S3_BUCKET'])

s3objects.each do |s3object|
  if s3object[:key] == ""
    bucket.object("index.html").put(body: s3object[:body])
  else
    bucket.object(s3object[:key]).put(body: s3object[:body])
  end
end
