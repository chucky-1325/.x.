fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nexus_territories'
author 'Nexus Creative Systems'
description 'Territorios NEXUS: influencia criminal, control por gang y estado por zonas.'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}
