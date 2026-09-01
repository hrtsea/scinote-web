# frozen_string_literal: true

module Scinote
  module AiProtocols
    # Extracts raw procedure text from an uploaded file so it can be fed to
    # ProtocolGenerator.
    #
    # Plain-text files (.txt/.text/.md/.markdown) are read directly. PDFs are
    # converted to text via the system `pdftotext` utility (poppler-utils) —
    # the same mechanism the host's ActiveStorage TextExtractionAnalyzer uses
    # (lib/active_storage/analyzer/text_extraction_analyzer.rb). If `pdftotext`
    # is missing, a clear ExtractionError is raised instead of failing silently.
    #
    # `source` must respond to #original_filename (or expose a #path) and #read,
    # i.e. an ActionDispatch::UploadedFile from a form upload.
    class TextExtractor
      PLAIN_TEXT_EXTENSIONS = %w[txt text md markdown].freeze
      PDF_EXTENSION = 'pdf'
      SUPPORTED_EXTENSIONS = (PLAIN_TEXT_EXTENSIONS + [PDF_EXTENSION]).freeze

      class UnsupportedFileType < StandardError; end
      class ExtractionError < StandardError; end

      def extract(source)
        ext = extension(source)
        unless SUPPORTED_EXTENSIONS.include?(ext)
          raise UnsupportedFileType,
                "Unsupported file type '.#{ext}' (expected one of: #{SUPPORTED_EXTENSIONS.join(', ')})"
        end

        ext == PDF_EXTENSION ? extract_pdf(source.path) : read_plain(source)
      end

      private

      def extension(source)
        name = source.respond_to?(:original_filename) ? source.original_filename : File.basename(source.path.to_s)
        File.extname(name.to_s).delete('.').downcase
      end

      def read_plain(source)
        source.rewind if source.respond_to?(:rewind)
        source.read.to_s
      end

      def extract_pdf(path)
        IO.popen(['pdftotext', path, '-'], 'r', &:read)
      rescue Errno::ENOENT
        raise ExtractionError, 'pdftotext is not installed; cannot extract text from PDF files'
      end
    end
  end
end
