i18n = import('i18n')

langs = ['pt_BR', 'es_ES', 'fr', 'de', 'it', 'ru']

foreach lang : langs
    custom_target(
        input: lang + '.po',
        output: 'dstx-gui.mo',   # <<--- Nome fixo do domínio
        command: [
            'msgfmt', '--check', '--verbose', '-o', '@OUTPUT@', '@INPUT@'
        ],
        install: true,
        install_dir: join_paths(localedir, lang, 'LC_MESSAGES')
    )
endforeach
