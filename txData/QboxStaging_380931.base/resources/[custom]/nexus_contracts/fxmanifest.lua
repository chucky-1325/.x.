fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nexus_contracts'
author 'Nexus Creative Systems'
description 'Contratos civiles trazables para el Vertical Slice NEXUS.'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/security_fallback.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

dependencies {
    'ox_lib',
    'oxmysql',
    'qbx_core',
    'ox_inventory',
}
