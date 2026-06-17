i18n = import('i18n')

langs = ['pt_BR', 'es_ES', 'fr', 'de', 'it', 'ru']

foreach lang : langs
    mo_file = custom_target(
        input: lang + '.po',
        output: lang + '.mo',
        command: [
            'msgfmt', '--check', '--verbose', '-o', '@OUTPUT@', '@INPUT@'
        ]
    )
    install_data(mo_file,
        install_dir: join_paths(localedir, lang, 'LC_MESSAGES'),
        rename: 'dstx-gui.mo'
    )
endforeach
