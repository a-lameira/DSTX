i18n = import('i18n')

langs = ['pt_BR', 'es_ES', 'fr', 'de', 'it', 'ru']

foreach lang : langs
    custom_target(
        input: lang + '.po',
        output: lang + '.mo',
        command: [
            'msgfmt', '--check', '--verbose', '-o', '@OUTPUT@', '@INPUT@'
        ],
        install: false
    )
endforeach
