module Hawkular
  # Specialized exception to be thrown
  # when the interaction with Hawkular fails
  class Exception < StandardError
    def initialize(message, status_code = 0)
      @message = message
      @status_code = status_code
      super(message)
    end

    attr_reader :message, :status_code
  end

  class ConnectionException < Exception
  end

  module ClientUtils
    # Escapes the passed url part. This is necessary,
    # as many ids inside Hawkular can contain characters
    # that are invalid for an url/uri.
    # The passed value is duplicated
    # Does not escape the = character
    # @param [String] url_part Part of an url to be escaped
    # @return [String] escaped url_part as new string
    def hawk_escape(url_part)
      return url_part.to_s if url_part.is_a?(Numeric)

      url_part
        .to_s
        .dup
        .gsub('%', '%25')
        .gsub(' ', '%20')
        .gsub('[', '%5b')
        .gsub(']', '%5d')
        .gsub('|', '%7c')
        .gsub('(', '%28')
        .gsub(')', '%29')
        .gsub('/', '%2f')
    end

    # Escapes the passed url part. This is necessary,
    # as many ids inside Hawkular can contain characters
    # that are invalid for an url/uri.
    # The passed value is duplicated
    # Does escape the = character
    # @param [String] url_part Part of an url to be escaped
    # @return [String] escaped url_part as new string
    def hawk_escape_id(url_part)
      hawk_escape(url_part)
        .gsub('=', '%3d')
        .gsub(';', '%3b')
    end
  end
end
