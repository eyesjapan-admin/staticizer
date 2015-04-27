require 'open-uri'
require 'net/http'

require 'ruby-wpdb'
require 'aws-sdk'

require 'dotenv'
Dotenv.load

WPDB.init("mysql2://#{ENV['DATABASE_USER']}:#{ENV['DATABASE_PASSWORD']}@#{ENV['DATABASE_HOST']}/#{ENV['DATABASE_NAME']}")

post_urls = WPDB::Post.all.select{ |post| (post.post_type == 'post' || post.post_type == 'page') && post.post_status == 'publish' }.map{ |post| post.guid }

posts = post_urls.map{ |url|
  response = Net::HTTP.get_response(URI.parse(url))

  case response
  when Net::HTTPSuccess
    html = response.body
  when Net::HTTPRedirection
    url = response['location']
    html = open(url).read
  end

  {url: url, html: html}
}

s3 = Aws::S3::Resource.new
bucket = s3.bucket(ENV['AWS_S3_BUCKET'])

posts.each do |post|
  object = bucket.object(post[:url])
  object.put(body: post[:html])
end
