require 'net/http'
require 'uri'

def get_redirected_url(unredirected_url)
  response = Net::HTTP.get_response(URI.parse(unredirected_url))

  case response
  when Net::HTTPRedirection
    return response['location']
  else
    return unredirected_url
  end
end


# http://example.com/?q=hoge&page=1 -> http://example.com/_q=hoge&page=1
def remove_queries(url_including_query)
  url_including_query.gsub(/\?/, '_')
end


# http://source.example.com/hoge/piyo -> http://target.example.com/hoge/piyo
def convert_site_url(source_site_url, target_site_url, url)
  return target_site_url + url[source_site_url.length .. -1]
end


# http://example.com/hoge/piyo/fuga.txt -> hoge/piyo/fuga.txt
def calc_s3object_key(site_url, url)
  return url[(site_url.length + 1) .. -1]
end
