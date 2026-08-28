fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nexus_dutyboard'
author 'Nexus Creative Systems'
description 'Punto de fichaje neutral para mecanicos.'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
}

server_scripts {
    'server/security_fallback.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

dependencies {
    'ox_lib',
    'qbx_core',
    'ox_target',
    'nexus_bridge',
}
