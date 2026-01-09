fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lf_emsplus'
author 'Lexfall'
description 'Lexfall Premium EMS System (NPC Calls, Phone Accept, Transport, Fame Hooks)'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

dependencies {
    'ox_lib',
    'ox_target',
    'qbx_core'
}
