require 'optparse'

require 'dotenv'
require 'aws-sdk'

Dotenv.load

params = ARGV.getopts('', 'clean', 'list')

s3 = Aws::S3::Resource.new
bucket = s3.bucket(ENV['AWS_S3_BUCKET'])

if params['clean']
  bucket.objects.each do |object_summary|
    object_summary.object.delete
  end
end

if params['list']
  bucket.objects.each do |object_summary|
    puts object_summary.key
  end
end
