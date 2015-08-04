require 'open-uri'

require 'dotenv'
require 'nokogiri'
require 'addressable/uri'

require './util' # convert_site_url, belong_to?


Dotenv.load


source_site_url = ENV['SOURCE_SITE_URL']
target_site_url = ENV['TARGET_SITE_URL']
cdn_site_url = ENV['CDN_SITE_URL']

source_site_url = source_site_url[0..-2] if source_site_url.end_with?('/')
target_site_url = target_site_url[0..-2] if target_site_url.end_with?('/')
cdn_site_url =    cdn_site_url[0..-2]    if cdn_site_url.end_with?('/')

input_dir        = Pathname(ENV['PATH_INPUT_DIR'])
output_dir_html  = Pathname(ENV['PATH_OUTPUT_DIR']) + 'html'
output_dir_cdn   = Pathname(ENV['PATH_OUTPUT_DIR']) + 'cdn'


Pathname.glob(input_dir + '**' + '*').select(&:file?).each do |path|
  output_html_path = output_dir_html + path.relative_path_from(input_dir)
  output_cdn_path  = output_dir_cdn  + path.relative_path_from(input_dir)

  if path.extname == '.html'
    nokogiried = Nokogiri::HTML(path.open)

    attrs = nokogiried.xpath('//@href | //@src').select{ |attr| belong_to?(source_site_url, attr.value) }

    attrs.each do |attr|
      attr_url = Addressable::URI.parse(attr.value)
      if attr.parent.name == 'a' and (attr_url.extname == '' or attr_url.extname == '.html')
        attr.value = convert_site_url(source_site_url, target_site_url, attr.value)
      else
        attr.value = convert_site_url(source_site_url, cdn_site_url, attr.value)
      end
    end

    FileUtils.mkdir_p(output_html_path.dirname) unless output_html_path.dirname.exist?
    open(output_html_path, 'w') do |file|
      file.write(nokogiried.to_html)
    end
  else
    FileUtils.mkdir_p(output_cdn_path.dirname) unless output_cdn_path.dirname.exist?
    FileUtils.copy(path, output_cdn_path)
  end
end
