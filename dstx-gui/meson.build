# meson.build - DSTX GUI build configuration
#
# Copyright (C) 2026 André Lameira
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# RESPONSIBILITIES:
# - Configure build system for DSTX GUI
# - Manage dependencies, sources, resources, and installation paths
# - Handle Flatpak-specific options and internationalization

project('dstx-gui', 'vala', 'c',
    version: '0.1.0',
    meson_version: '>= 0.50.0',
    license: 'GPL3',
    default_options: [
        'warning_level=3',
        'buildtype=debugoptimized'
    ]
)

# ==================== CONFIGURATION OPTIONS ====================
flatpak = get_option('flatpak')

# ==================== PROJECT CONFIGURATIONS ====================
prefix = get_option('prefix')
datadir = prefix / get_option('datadir')
icondir = datadir / 'icons/hicolor/symbolic/apps'
applications_dir = datadir / 'applications'
localedir = prefix / 'share' / 'locale'

# ==================== INTERNATIONALIZATION ====================
gettext_domain = 'dstx-gui'

# For C compiler
add_project_arguments(
    '-DGETTEXT_PACKAGE="@0@"'.format(gettext_domain),
    '-DLOCALEDIR="@0@"'.format(localedir),
    language: 'c'
)

# For Vala compiler (using --define=)
add_project_arguments(
    '--define=GETTEXT_PACKAGE="@0@"'.format(gettext_domain),
    '--define=LOCALEDIR="@0@"'.format(localedir),
    language: 'vala'
)

# Include translations subdirectory
subdir('po')

# ==================== C COMPILER ====================
cc = meson.get_compiler('c')

# ==================== GLOBAL ARGUMENTS ====================
if get_option('buildtype') == 'debug' or get_option('buildtype') == 'debugoptimized'
    add_project_arguments('--debug', language: 'vala')
    add_project_arguments('-g', language: 'c')
endif

c_args = [
    '-DGETTEXT_PACKAGE="' + gettext_domain + '"',
    '-DG_LOG_DOMAIN="dstx-gui"',
    '-Wall',
    '-Wextra',
]
add_project_arguments(c_args, language: 'c')

# ==================== DEPENDENCIES ====================
dependencies = [
    dependency('glib-2.0', version: '>= 2.58'),
    dependency('gobject-2.0', version: '>= 2.58'),
    dependency('gio-2.0', version: '>= 2.58'),
    dependency('gio-unix-2.0', version: '>= 2.58'),
    dependency('gtk4', version: '>= 4.0.0'),
    dependency('libadwaita-1', version: '>= 1.4.0'),
    dependency('gee-0.8', version: '>= 0.20.0'),
    dependency('json-glib-1.0', version: '>= 1.6'),
    dependency('librsvg-2.0', version: '>= 2.48'),
]

m_dep = cc.find_library('m', required: true)

foreach dep : dependencies
    if dep.type_name() == 'pkgconfig'
        assert(dep.found(), 'Dependency @0@ not found'.format(dep.name()))
    endif
endforeach

# ==================== SOURCE DIRECTORIES ====================
src_dir = include_directories('src')
core_dir = include_directories('src/core')
widgets_dir = include_directories('src/widgets')
models_dir = include_directories('src/models')
view_models_dir = include_directories('src/view-models')
managers_dir = include_directories('src/managers')
services_dir = include_directories('src/services')

# ==================== VALA SOURCES ====================
vala_sources = files(
    'src/main.vala',
    'src/application.vala',
    'src/window.vala',
    'src/dstx-dbus-interface.vala',
    'src/i18n.vala',
    'src/core/settings-manager.vala',
    'src/core/dbus-client.vala',
    'src/core/locale-manager.vala',
    'src/core/system-service-manager.vala',
    'src/core/flatpak-utils.vala',
    'src/models/controller.vala',
    'src/models/controller-info.vala',
    'src/models/theme-data.vala',
    'src/view-models/controller-view-model.vala',
    'src/widgets/controller-card.vala',
    'src/widgets/radar-widget.vala',
    'src/widgets/color-picker-widget.vala',
    'src/widgets/color-picker-dialog.vala',
    'src/widgets/keybinds-dialog.vala',
    'src/widgets/about-dialog.vala',
    'src/widgets/update-dialog.vala',
    'src/widgets/donations-dialog.vala',
    'src/widgets/tips-dialog.vala',
    'src/widgets/appearance-page.vala',
    'src/widgets/profiles-dialog.vala',
    'src/widgets/sticky-header.vala',
    'src/widgets/dualsense.vala',
    'src/widgets/ds4.vala',
    'src/widgets/nsw.vala',
    'src/managers/app-state-manager.vala',
    'src/managers/controller-manager.vala',
    'src/managers/settings-controller.vala',
    'src/managers/settings-ui-builder.vala',
    'src/managers/theme-manager.vala',
    'src/managers/profile-manager.vala',
    'src/managers/keybinds-manager.vala',
    'src/services/svg-colorizer.vala',
    'src/services/controller-renderer.vala',
    'src/services/thumbnail-renderer.vala',
    'src/services/texture-cache-manager.vala',
)

# ==================== VALAC ARGUMENTS ====================
vala_args = [
    '--vapidir=' + meson.current_source_dir() / 'vapi',
    '--pkg=linux',
    '--target-glib=2.58',
    '--enable-experimental',
]

vala_args += [
    '--includedir=' + meson.current_source_dir() / 'src',
    '--includedir=' + meson.current_source_dir() / 'src/core',
    '--includedir=' + meson.current_source_dir() / 'src/widgets',
    '--includedir=' + meson.current_source_dir() / 'src/models',
    '--includedir=' + meson.current_source_dir() / 'src/view-models',
    '--includedir=' + meson.current_source_dir() / 'src/managers',
    '--includedir=' + meson.current_source_dir() / 'src/services',
]

# ==================== RESOURCE FILES ====================
gnome = import('gnome')

resources = gnome.compile_resources(
    'resources',
    'data/dstx.gresource.xml',
    source_dir: 'data',
    c_name: 'dstx',
    export: true
)

# ==================== MAIN EXECUTABLE ====================
executable('dstx-gui',
    vala_sources,
    resources,
    dependencies: dependencies,
    vala_args: vala_args,
    include_directories: [src_dir, core_dir, widgets_dir, models_dir, managers_dir, services_dir],
    install: true,
    install_dir: prefix / 'bin',
)

# ==================== INSTALL SCRIPTS (ONLY FLATPAK) ====================
if flatpak
    install_data('scripts/install-system-components.sh',
        install_dir: prefix / 'bin',
        install_mode: 'rwxr-xr-x'
    )
    install_data('scripts/uninstall-system-components.sh',
        install_dir: prefix / 'bin',
        install_mode: 'rwxr-xr-x'
    )
endif

# ==================== ICON FILES ====================
icondir_symbolic = datadir / 'icons/hicolor/symbolic/apps'

install_data('data/icons/ds4-symbolic.svg',
    install_dir: icondir_symbolic,
)

install_data('data/icons/dualsense-symbolic.svg',
    install_dir: icondir_symbolic,
)

install_data('data/icons/nsw-pro-symbolic.svg',
    install_dir: icondir_symbolic,
)

install_data('data/icons/symbolic-link-symbolic.svg',
    install_dir: icondir_symbolic,
)

install_data('data/icons/brush-monitor-symbolic.svg',
    install_dir: icondir_symbolic,
)

icondir_scalable = datadir / 'icons/hicolor/scalable/apps'

install_data('data/icons/ds4-symbolic.svg',
    install_dir: icondir_scalable,
    rename: 'ds4-symbolic.svg'
)

install_data('data/icons/dualsense-symbolic.svg',
    install_dir: icondir_scalable,
    rename: 'dualsense-symbolic.svg'
)

install_data('data/icons/nsw-pro-symbolic.svg',
    install_dir: icondir_scalable,
    rename: 'nsw-pro-symbolic.svg'
)

install_data('data/icons/symbolic-link-symbolic.svg',
    install_dir: icondir_scalable,
    rename: 'symbolic-link-symbolic.svg'
)

install_data('data/icons/brush-monitor-symbolic.svg',
    install_dir: icondir_scalable,
    rename: 'symbolic-link-symbolic.svg'
)

# DualSense
install_subdir('data/icons/dualsense',
    install_dir: icondir_scalable / 'dualsense',
    strip_directory: false,
)

# DS4
install_subdir('data/icons/ds4',
    install_dir: icondir_scalable / 'ds4',
    strip_directory: false,
)

# NSW Pro
install_subdir('data/icons/nsw',
    install_dir: icondir_scalable / 'nsw',
    strip_directory: false,
)

# Themes
install_subdir('data/icons/themes',
    install_dir: icondir_scalable / 'themes',
    strip_directory: false,
)

# Theme data
install_data('data/themes.json',
    install_dir: datadir / 'dstx-gui',
)

if files('data/icons/dstx.svg').length() > 0
    if flatpak
        install_data('data/icons/dstx.svg',
            install_dir: icondir_scalable,
            rename: 'org.dstx.gui.svg'
        )
    else
        install_data('data/icons/dstx.svg',
            install_dir: icondir_scalable
        )
    endif
endif

# ==================== .DESKTOP FILE ====================
i18n = import('i18n')

if flatpak
    desktop_output = 'org.dstx.gui.desktop'
else
    desktop_output = 'dstx-gui.desktop'
endif

desktop_file = i18n.merge_file(
    input: 'data/dstx-gui.desktop.in',
    output: desktop_output,
    type: 'desktop',
    po_dir: meson.current_source_dir() / 'po',
    install: true,
    install_dir: applications_dir
)

# ==================== AppStream METADATA ====================
install_data('data/org.dstx.gui.appdata.xml',
    install_dir: datadir / 'metainfo'
)

# ==================== FILE CHECKS ====================
fs = import('fs')

symbolic_icons = [
    'data/icons/ds4-symbolic.svg',
    'data/icons/dualsense-symbolic.svg',
    'data/icons/nsw-pro-symbolic.svg',
    'data/icons/symbolic-link-symbolic.svg',
    'data/icons/brush-monitor-symbolic.svg'
]

foreach icon : symbolic_icons
    icon_path = meson.current_source_dir() / icon
    if not fs.exists(icon_path)
        warning('Icon @0@ not found'.format(icon))
    endif
endforeach

dualsense_base = meson.current_source_dir() / 'data/icons/dualsense/base.svg'
if not fs.exists(dualsense_base)
    warning('DualSense base.svg not found: ' + dualsense_base)
endif

ds4_base = meson.current_source_dir() / 'data/icons/ds4/base.svg'
if not fs.exists(ds4_base)
    warning('DS4 base.svg not found: ' + ds4_base)
endif

nsw_base = meson.current_source_dir() / 'data/icons/nsw/base.svg'
if not fs.exists(nsw_base)
    warning('NSW Pro base.svg not found: ' + nsw_base)
endif

css_path = meson.current_source_dir() / 'data/themes/theme-base.css'
if not fs.exists(css_path)
    warning('CSS base not found: ' + css_path)
endif

json_path = meson.current_source_dir() / 'data/themes.json'
if not fs.exists(json_path)
    error('Themes JSON file not found: ' + json_path)
endif

desktop_in_path = meson.current_source_dir() / 'data/dstx-gui.desktop.in'
if not fs.exists(desktop_in_path)
    error('Desktop file template not found: ' + desktop_in_path)
endif

# ==================== CONFIGURATION REPORT ====================
message('\n==================== DIRECTORIES ====================')
message('Prefix:          ' + prefix)
message('Datadir:         ' + datadir)
message('Localedir:       ' + localedir)
message('Icons:           ' + icondir)
message('Applications:    ' + applications_dir)
message('Version:         ' + meson.project_version())
message('Build type:      ' + get_option('buildtype'))

message('\n==================== DEPENDENCIES ====================')
message('glib-2.0:        ' + dependencies[0].version())
message('gtk4:            ' + dependencies[4].version())
message('libadwaita-1:    ' + dependencies[5].version())
message('gee-0.8:         ' + dependencies[6].version())
message('json-glib-1.0:   ' + dependencies[7].version())
message('librsvg-2.0:     ' + dependencies[8].version())
message('libm:            added')
message('')

message('==================== SOURCES ====================')
source_list = ''
foreach src : vala_sources
    if src.full_path() != ''
        source_list += ' ' + src.full_path()
    endif
endforeach
message('Vala sources:   ' + source_list)
message('')

message('==================== CONTROLLER ASSETS ====================')
message('DualSense:      base.svg')
message('DS4:            base.svg')
message('NSW Pro:        base.svg')
message('')

message('==================== THEME SYSTEM ====================')
message('Theme definitions: themes.json')
message('')

message('==================== CONFIGURATION STORAGE ====================')
message('Config directory: ~/.config/dstx/')
message('Config file:      ~/.config/dstx/settings.json')
message('')

message('==================== BUILD COMPLETE ====================')
message('To run:           ninja -C builddir run')
message('To install:       ninja -C builddir install')
message('')

# ==================== CUSTOM TARGETS ====================
run_target('run',
    command: ['sh', '-c', meson.current_build_dir() / 'dstx-gui']
)

run_target('check',
    command: ['valac', '--vapidir=' + meson.current_source_dir() / 'vapi', 
              '--pkg=gtk4', '--pkg=libadwaita-1', '--pkg=gee-0.8',
              '--pkg=gio-2.0', '--pkg=gio-unix-2.0', '--pkg=librsvg-2.0',
              '--pkg=json-glib-1.0', '--pkg=linux', '--syntax'] + vala_sources,
    depends: []
)

run_target('list-resources',
    command: ['glib-compile-resources', '--sourcedir=' + meson.current_source_dir() / 'data',
              '--generate-dependencies', meson.current_source_dir() / 'data/dstx.gresource.xml'],
    depends: []
)

meson.add_install_script('sh', '-c', 'mkdir -p "$MESON_INSTALL_DESTDIR_PREFIX"/@0@'.format(icondir))
meson.add_install_script('sh', '-c', 'mkdir -p "$MESON_INSTALL_DESTDIR_PREFIX"/@0@'.format(applications_dir))
meson.add_install_script('sh', '-c', 'mkdir -p "$MESON_INSTALL_DESTDIR_PREFIX"/@0@'.format(icondir_scalable))
