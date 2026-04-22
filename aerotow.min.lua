[619:3] unexpected identifier 'continue' near 'local'

Error: failed to minify. Make sure the Lua code is valid.
If you think this is a bug in luamin, please report it:
https://github.com/mathiasbynens/luamin/issues/new

Stack trace using luamin@1.0.4 and luaparse@0.2.1:

SyntaxError: [619:3] unexpected identifier 'continue' near 'local'
    at raise (/usr/local/share/nvm/versions/node/v24.14.0/lib/node_modules/luamin/node_modules/luaparse/luaparse.js:460:15)
    at unexpected (/usr/local/share/nvm/versions/node/v24.14.0/lib/node_modules/luamin/node_modules/luaparse/luaparse.js:512:14)
    at parseAssignmentOrCallStatement (/usr/local/share/nvm/versions/node/v24.14.0/lib/node_modules/luamin/node_modules/luaparse/luaparse.js:1624:12)
    at parseStatement (/usr/local/share/nvm/versions/node/v24.14.0/lib/node_modules/luamin/node_modules/luaparse/luaparse.js:1316:12)
    at parseBlock (/usr/local/share/nvm/versions/node/v24.14.0/lib/node_modules/luamin/node_modules/luaparse/luaparse.js:1271:19)
    at parseIfStatement (/usr/local/share/nvm/versions/node/v24.14.0/lib/node_modules/luamin/node_modules/luaparse/luaparse.js:1419:12)
    at parseStatement (/usr/local/share/nvm/versions/node/v24.14.0/lib/node_modules/luamin/node_modules/luaparse/luaparse.js:1292:41)
    at parseBlock (/usr/local/share/nvm/versions/node/v24.14.0/lib/node_modules/luamin/node_modules/luaparse/luaparse.js:1271:19)
    at parseForStatement (/usr/local/share/nvm/versions/node/v24.14.0/lib/node_modules/luamin/node_modules/luaparse/luaparse.js:1507:14)
    at parseStatement (/usr/local/share/nvm/versions/node/v24.14.0/lib/node_modules/luamin/node_modules/luaparse/luaparse.js:1298:41)
