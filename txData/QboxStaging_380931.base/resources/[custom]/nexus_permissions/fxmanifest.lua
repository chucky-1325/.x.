fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nexus_permissions'
description 'Fase 1: catalogo de roles y grant/revoke por citizenid, sin autorizacion de gameplay todavia.'
author 'Nexus Creative Systems'
version '0.1.0'

dependencies {
    'oxmysql',
    'qbx_core',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config.lua',
    'server/main.lua',
}
