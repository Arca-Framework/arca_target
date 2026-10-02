fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'arca_target'
author 'Arca'
description 'Third-eye targeting for the Arca framework'
version '0.1.0'

shared_script 'config.lua'

client_scripts {
    'client/api.lua',
    'client/main.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
}

dependencies {
    'arca_core',
}
