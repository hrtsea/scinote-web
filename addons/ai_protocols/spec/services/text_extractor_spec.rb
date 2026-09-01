# frozen_string_literal: true

require 'rails_helper'

module Scinote
  module AiProtocols
    RSpec.describe TextExtractor do
      subject(:extractor) { described_class.new }

      def uploaded_file(content, filename)
        temp = Tempfile.new(['ai_proto', File.extname(filename)])
        temp.write(content)
        temp.rewind
        (@files ||= []) << temp
        Rack::Test::UploadedFile.new(temp.path, 'text/plain', original_filename: filename)
      end

      after do
        Array(@files).each(&:close!)
      end

      describe '#extract' do
        it 'reads a plain-text (.txt) file' do
          file = uploaded_file('Lyse cells with 100 uL buffer.', 'sop.txt')
          expect(extractor.extract(file)).to eq('Lyse cells with 100 uL buffer.')
        end

        it 'reads a markdown (.md) file' do
          file = uploaded_file("# Title\nStep one.", 'notes.md')
          expect(extractor.extract(file)).to eq("# Title\nStep one.")
        end

        it 'extracts a PDF via pdftotext' do
          file = uploaded_file('%PDF-1.4', 'doc.pdf')
          allow(extractor).to receive(:extract_pdf).with(file.path).and_return('PDF body text')
          expect(extractor.extract(file)).to eq('PDF body text')
        end

        it 'raises UnsupportedFileType for unknown extensions' do
          file = uploaded_file('sheet data', 'sheet.xlsx')
          expect { extractor.extract(file) }
            .to raise_error(TextExtractor::UnsupportedFileType, /xlsx/)
        end

        it 'raises ExtractionError when pdftotext is missing' do
          file = uploaded_file('%PDF-1.4', 'doc.pdf')
          allow(IO).to receive(:popen).with(['pdftotext', file.path, '-'], 'r').and_raise(Errno::ENOENT)
          expect { extractor.extract(file) }
            .to raise_error(TextExtractor::ExtractionError, /pdftotext/)
        end
      end
    end
  end
end
