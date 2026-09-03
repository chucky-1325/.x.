fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nexus_crafting'
author 'Nexus Creative Systems'
description 'Banco mecanico NEXUS para el Vertical Slice de suministros.'
version '1.0.0'

ui_page './html/index.html'

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

file './html/index.html'
file './html/style.css'
file './html/app.js'

dependencies {
    'ox_lib',
    'oxmysql',
    'qbx_core',
    'ox_inventory',
}
