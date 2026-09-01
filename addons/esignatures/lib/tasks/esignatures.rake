# frozen_string_literal: true

namespace :esignatures do
  desc 'Verify the electronic-signature chain for a record: rake esignatures:verify[Protocol,123]'
  task :verify, %i(signable_type signable_id) => :environment do |_t, args|
    record = args[:signable_type].constantize.find(args[:signable_id])
    report = Scinote::Esignatures::ChainVerifier.verify(record)
    if report[:valid]
      puts "VALID — #{record.class}##{record.id} " \
           "(record tampered since signing: #{report[:record_modified]})"
    else
      puts "INVALID — #{report[:error]}"
    end
  end

  desc 'Export an electronic-signature proof for a record: rake esignatures:export[Protocol,123]'
  task :export, %i(signable_type signable_id) => :environment do |_t, args|
    record = args[:signable_type].constantize.find(args[:signable_id])
    Scinote::Esignatures::ExportProof.call(record)
  end
end
