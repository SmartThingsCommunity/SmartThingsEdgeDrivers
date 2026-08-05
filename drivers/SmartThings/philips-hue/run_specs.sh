#!/bin/sh

export LUA_PATH="./test/spec/?.lua;./test/spec/?/init.lua;./src/?.lua;./src/?/init.lua;$LUA_LIBS/?.lua;$LUA_LIBS/?/init.lua;;"

~/.luarocks/bin/busted -C 'src' -m "$LUA_PATH" -k -v './test/spec'
