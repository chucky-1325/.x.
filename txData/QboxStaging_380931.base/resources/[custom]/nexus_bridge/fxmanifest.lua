fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nexus_bridge'
author 'Nexus Creative Systems'
description 'Core tecnico NEXUS: bridge QBox/OX, permisos, rate limit y helpers compartidos.'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'shared/constants.lua',
    'shared/utils.lua',
}

server_scripts {
    'server/security.lua',
    'server/permissions.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}
