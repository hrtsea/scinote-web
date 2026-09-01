# Temporary override for offline production container:
# CSS/JS artifacts already exist in app/assets/builds from image build time,
# so the yarn-based install/build tasks are skipped here.
# (github.com is unreachable in the container, which made yarn install fail.)
Rake::Task['css:install'].clear
Rake::Task['css:install'].enhance do
  # no-op
end
Rake::Task['css:build'].clear
Rake::Task['css:build'].enhance do
  # no-op
end
Rake::Task['javascript:install'].clear
Rake::Task['javascript:install'].enhance do
  # no-op
end
Rake::Task['javascript:build'].clear
Rake::Task['javascript:build'].enhance do
  # no-op
end
