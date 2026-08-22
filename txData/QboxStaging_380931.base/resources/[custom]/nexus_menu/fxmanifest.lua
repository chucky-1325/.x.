fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nexus_menu'
author 'Nexus Creative Systems'
description 'Menu central NEXUS para abrir herramientas inmersivas y pruebas del servidor.'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}
