fx_version 'cerulean'
game 'gta5'

lua54 'yes'

description 'NEXUS Dispatch - alertas policiales centralizadas'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/main.lua'
}

client_scripts {
    'client/main.lua'
}
