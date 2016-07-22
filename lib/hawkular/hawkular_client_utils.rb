module HawkularUtilsMixin
  # Escapes the passed url part. This is necessary,
  # as many ids inside Hawkular can contain characters
  # that are invalid for an url/uri.
  # The passed value is duplicated
  # Does not escape the = character
  # @param [String] url_part Part of an url to be escaped
  # @return [String] escaped url_part as new string
  def hawk_escape(url_part)
    return url_part.to_s if url_part.is_a?(Numeric)

    if url_part.is_a? Symbol
      sub_url = url_part.to_s
    else
      sub_url = url_part.dup
    end
    sub_url.gsub!('%', '%25')
    sub_url.gsub!(' ', '%20')
    sub_url.gsub!('[', '%5b')
    sub_url.gsub!(']', '%5d')
    sub_url.gsub!('|', '%7c')
    sub_url.gsub!('(', '%28')
    sub_url.gsub!(')', '%29')
    sub_url.gsub!('/', '%2f')
    sub_url
  end

  # Escapes the passed url part. This is necessary,
  # as many ids inside Hawkular can contain characters
  # that are invalid for an url/uri.
  # The passed value is duplicated
  # Does escape the = character
  # @param [String] url_part Part of an url to be escaped
  # @return [String] escaped url_part as new string
  def hawk_escape_id(url_part)
    sub_url = hawk_escape url_part
    sub_url.gsub!('=', '%3d')
    sub_url.gsub!(';', '%3b')
    sub_url
  end
end
