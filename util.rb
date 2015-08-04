require 'addressable/uri'

# http://source.example.com/hoge/piyo -> http://target.example.com/hoge/piyo
# //source.example.com/hoge/piyo -> http://target.example.com/hoge/piyo
def convert_site_url(source_site_url, target_site_url, url)
  url_parsed = Addressable::URI.parse(url)
  return url if url_parsed.relative?

  url_parsed.scheme = Addressable::URI.parse(source_site_url).scheme
  url = url_parsed.to_s

  if url.start_with?(source_site_url)
    return target_site_url + url[source_site_url.length .. -1]
  else
    return url
  end
end

def belong_to?(base_url, url)
  url_parsed = Addressable::URI.parse(url)
  return true if url_parsed.relative?

  url_parsed.scheme = Addressable::URI.parse(base_url).scheme

  return url_parsed.to_s.start_with?(base_url)
end
