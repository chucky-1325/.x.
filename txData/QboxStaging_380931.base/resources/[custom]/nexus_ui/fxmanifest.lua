fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nexus_ui'
author 'Nexus Creative Systems'
description 'Design system compartido NEXUS para NUI, notificaciones y tokens visuales.'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'shared/tokens.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}
