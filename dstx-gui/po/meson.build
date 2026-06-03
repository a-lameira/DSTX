i18n = import('i18n')

# Lista de idiomas suportados
langs = ['pt_BR', 'es_ES', 'fr', 'de', 'it', 'ru']

foreach lang : langs
    # Compila explicitamente cada .po para .mo usando custom_target
    custom_target(
        input: lang + '.po',
        output: lang + '.mo',
        command: [
            'msgfmt', '--check', '--verbose', '-o', '@OUTPUT@', '@INPUT@'
        ],
        install: true,
        install_dir: join_paths(localedir, lang, 'LC_MESSAGES')
    )
endforeach
