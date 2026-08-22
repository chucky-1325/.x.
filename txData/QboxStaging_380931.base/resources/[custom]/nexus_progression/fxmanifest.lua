fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nexus_progression'
author 'Nexus Creative Systems'
description 'Progresion persistente NEXUS: XP, niveles y reputacion por dominio.'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'shared/utils.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}
