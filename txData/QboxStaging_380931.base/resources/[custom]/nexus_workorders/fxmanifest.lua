fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nexus_workorders'
author 'Nexus Creative Systems'
description 'Motor universal de ordenes de trabajo NEXUS: cola P2P, escrow, outbox y auditoria compartida para EMS, policia, mecanica, transporte, empresas y justicia.'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
}

dependencies {
    'qbx_core',
    'ox_lib',
    'oxmysql',
}
