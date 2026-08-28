fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nexus_operations'
author 'Nexus Creative Systems'
description 'Operaciones de banda NEXUS: suministros, extorsion, riesgo territorial y recompensas grupales.'
version '0.1.0'

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
    'nexus_bridge',
    'ox_inventory',
}
