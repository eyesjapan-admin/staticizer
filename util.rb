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
def remove_query(url_including_query)
  url_including_query.gsub(/\?/, '_')
end


# http://example.com/#hoge -> http://example.com/
def remove_fragment(url_including_fragment)
  uri = URI.parse(url_including_fragment)
  if uri.query
    return "#{uri.scheme}://#{uri.host}#{uri.path}?#{uri.query}"
  else
    return "#{uri.scheme}://#{uri.host}#{uri.path}"
  end
end


# http://source.example.com/hoge/piyo -> http://target.example.com/hoge/piyo
def convert_site_url(source_site_url, target_site_url, url)
  return target_site_url + url[source_site_url.length .. -1]
end


# http://example.com/hoge/piyo/fuga.txt -> hoge/piyo/fuga.txt
# http://example.com/hoge/piyo/ -> hoge/piyo/index.html
def calc_s3object_key(site_url, url)
  site_url_omitted_url = url[(site_url.length + 1) .. -1]

  if site_url_omitted_url.end_with?('/')
    return site_url_omitted_url + 'index.html'
  else
    return site_url_omitted_url
  end
end
