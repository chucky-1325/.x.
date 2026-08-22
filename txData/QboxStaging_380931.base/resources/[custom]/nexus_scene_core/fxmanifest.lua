fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nexus_scene_core'
author 'Nexus Creative Systems'
description 'Nucleo reutilizable de escenas fisicas, animaciones y props para NEXUS.'
version '0.1.0'

dependency 'ox_lib'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/constants.lua',
    'shared/utils.lua',
    'config/config.lua',
    'config/scenes.lua',
    'locales/es.lua',
}

client_scripts {
    'client/functions.lua',
    'client/main.lua',
}

server_scripts {
    'server/security.lua',
    'server/main.lua',
}
