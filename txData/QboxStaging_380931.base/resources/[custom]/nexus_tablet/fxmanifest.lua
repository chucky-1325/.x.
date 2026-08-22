fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nexus_tablet'
author 'Nexus Creative Systems'
description 'Shell modular para tablets inmersivas: policia, EMS, ilegal y empresas.'
version '0.1.0'

ui_page 'html/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'shared/apps.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
