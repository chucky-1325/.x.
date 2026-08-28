fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nexus_ems'
author 'Nexus Creative Systems'
description 'Sistema clinico NEXUS: evaluacion, tratamiento, progresion y auditoria EMS.'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/constants.lua',
    'shared/utils.lua',
    'config/config.lua',
    'config/jobs.lua',
    'locales/es.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/security_fallback.lua',
    'server/functions.lua',
    'server/callbacks.lua',
    'server/events.lua',
    'server/main.lua',
}

client_scripts {
    'client/functions.lua',
    'client/menu.lua',
    'client/target.lua',
    'client/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

dependencies {
    'qbx_core',
    'ox_lib',
    'oxmysql',
    'ox_inventory',
    'ox_target',
    'nexus_scene_core',
}

