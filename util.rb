require 'net/http'

require 'addressable/uri'

def get_redirected_url(unredirected_url)
  response = Net::HTTP.get_response(Addressable::URI.parse(unredirected_url))

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
  uri = Addressable::URI.parse(url_including_fragment)
  if uri.query
    return "#{uri.scheme}://#{uri.host}#{uri.path}?#{uri.query}"
  else
    return "#{uri.scheme}://#{uri.host}#{uri.path}"
  end
end


# http://source.example.com/hoge/piyo -> http://target.example.com/hoge/piyo
def convert_site_url(source_site_url, target_site_url, url)
  if url.start_with?(source_site_url)
    return target_site_url + url[source_site_url.length .. -1]
  else
    return url
  end
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


# "p.hoge { background-image: url(\"../img/hoge.png\"); } p.piyo { background-image: url('http://www.example.com/img/piyo.png'); }" -> ["../img/hoge.png", "http://www.example.com/img/piyo.png"]
def extract_urls_from_css(css_content)
  return css_content.scan(/url\(['"](.*?)['"]\)/).flatten
end
