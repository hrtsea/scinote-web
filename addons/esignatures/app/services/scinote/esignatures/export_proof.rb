# frozen_string_literal: true

module Scinote
  module Esignatures
    # Produces a human-readable, self-verifying proof of the signature chain.
    # The printed proof restates every signature event plus its recomputed
    # verification status, so an auditor can confirm integrity offline.
    class ExportProof
      def self.call(signable, io: $stdout)
        report = ChainVerifier.verify(signable)
        records = Scinote::Esignatures::ESignatureRecord
                  .where(signable: signable)
                  .order(created_at: :asc, id: :asc)

        lines = []
        lines << '=============================================='
        lines << ' Electronic Signature Proof (21 CFR Part 11)'
        lines << '=============================================='
        lines << "Generated:      #{Time.now.utc.iso8601}"
        lines << "Signed record: #{signable.class.name}##{signable.id}"
        lines << "Signatures:    #{records.count}"
        lines << "Chain valid:   #{report[:valid]}"
        lines << "Record tampered since signing: #{report[:record_modified]}"
        lines << ''

        records.each do |rec|
          lines << "--- Signature ##{rec.id} ---"
          lines << "Signer:        #{rec.user&.email || rec.user_id}"
          lines << "Signed at:     #{rec.signed_at&.iso8601}"
          lines << "Intent:        #{rec.meaning}"
          lines << "Previous hash: #{rec.previous_hash}"
          lines << "Record hash:   #{rec.record_hash}"
          lines << "Signature hash:#{rec.signature_hash}"
          lines << ''
        end

        lines << (report[:valid] ? 'STATUS: VALID' : "STATUS: INVALID — #{report[:error]}")
        lines << '=============================================='

        output = lines.join("\n")
        io&.puts(output)
        output
      end
    end
  end
end
