require "yaml"

namespace :i18n do

  desc "Find unused keys for given locale (default: 'en'); currently only works on OSs that support 'grep' command"
  task :unused_keys, [ :lang ] => :environment do |_, args|

    def flatten_hash(my_hash, parent=[])
      my_hash.flat_map do |key, value|
        case value
          when Hash then flatten_hash(value, parent + [key])
          else [(parent + [key]).join("."), value]
        end
      end
    end

    lang = args[:lang] || "en"
    all_files = Dir.entries("config/locales").select { |f| f.ends_with?("#{lang}.yml") }
    all_keys = []

    all_files.each do |fname|
      yml = YAML.load_file("config/locales/#{fname}")
      res = Hash[*flatten_hash(yml)]
      res.keys.each do |key|
        all_keys << (key.start_with?("#{lang}.") ? key.sub("#{lang}.", "") : key)
      end
    end

    all_good = true
    all_keys.each do |key|
      `grep -rn #{key} .`
      next if $CHILD_STATUS.successful?

      if all_good
        all_good = false
        puts "Following keys are unused (for locale #{lang}):"
      end
      puts "  #{key}"
    end

    if all_good
      puts "No unused keys found!"
    end
  end

  desc "Compare translation keys between the default locale and all other locales (missing / extra / blank values). " \
       "Works even when I18n fallbacks are enabled, because it compares the raw translation key sets instead of calling I18n.translate."
  task :missing_keys => :environment do

    flatten = lambda do |hash, prefix, out|
      hash.each do |key, value|
        current = prefix + [key.to_s]
        if value.is_a?(Hash)
          flatten.call(value, current, out)
        else
          out << [current.join('.'), value]
        end
      end
    end

    # Make sure we've loaded the translations
    I18n.backend.send(:init_translations)
    translations = I18n.backend.send(:translations)
    default_locale = I18n.default_locale.to_s
    locales = translations.keys.map(&:to_s).sort

    keysets = {}
    locales.each do |locale|
      flat = []
      flatten.call(translations[locale.to_sym], [], flat)
      keysets[locale] = flat
    end

    base = keysets.fetch(default_locale, []).map(&:first)
    puts "#{locales.size} #{locales.size == 1 ? 'locale' : 'locales'} available: #{locales.to_sentence}"
    puts "#{base.size} keys in default locale (#{default_locale}):"

    locales.each do |locale|
      keys = keysets[locale].map(&:first)
      missing = base - keys
      extra = keys - base
      blank = keysets[locale].select { |_k, v| v.is_a?(String) && v.strip.empty? }.map(&:first)

      covered = (keys & base).size
      coverage = base.empty? ? 100.0 : (covered.to_f / base.size * 100).round(1)
      puts format('  %-9s keys: %-6d coverage: %-7s missing: %-4d extra: %-4d blank: %d',
                  locale, keys.size, "#{coverage}%", missing.size, extra.size, blank.size)

      unless missing.empty?
        puts '    missing:'
        missing.group_by { |k| k.split('.').first }.sort_by { |_g, ks| -ks.size }.each do |group, ks|
          puts format('      %-24s %3d  %s', "#{group}:", ks.size, ks.first(5).join(', '))
        end
      end
      puts "    extra: #{extra.join(', ')}" unless extra.empty?
      puts "    blank: #{blank.join(', ')}" unless blank.empty?
    end

  end
end
