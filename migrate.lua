-- Migration utility
-- =================
--
-- This utility helps migrate records from the old cloud into the new one.
-- Not meant to be used from Lapis but as a command-line utility.
--
-- written by Bernat Romagosa
--
-- Copyright (C) 2017 by Bernat Romagosa
--
-- This file is part of Snap Cloud.
--
-- Snap Cloud is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as
-- published by the Free Software Foundation, either version 3 of
-- the License, or (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Affero General Public License for more details.
--
-- You should have received a copy of the GNU Affero General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

local pgmoon = require('pgmoon')
local xml = require('xml')
local url = os.getenv('DATABASE_URL')
local table = arg[1] or nil
local filename = arg[2] or nil
local file = io.open(filename, 'r')
local file_size
local buffer_size = tonumber(arg[3]) or 393216 -- Seems to be the sweet spot in my system
local usage = 'Usage:\n\nlua migrate.lua [users/projects/mediae] [file.xml] [buffer size]\n'

require 'disk'

local db = pgmoon.new({
    host = url:match("([^:]*)"), -- only up to ":"
    port = url:match("^.*%:(.*)"), -- after ":"
    database = os.getenv('DATABASE_NAME'),
    user = os.getenv('DATABASE_USERNAME'),
    password = os.getenv('DATABASE_PASSWORD')
})

assert(db:connect())

if not (arg[1] and arg[2]) then
    print(usage)
end

if file then
    file_size = file:seek('end')
    file:seek('set', 0)
else
    print('Could not read ' .. filename)  
    print(usage)
    os.exit()
end

function migrate_collection(entities)
    local separator = {
        users = "\0",
        mediae = "\3",
        projects = "\3"
    }

    local file_position = 1

    while file_position < file_size do
        local index = nil
        local raw_item = ''
        local buffer = ''
        file:seek('set', file_position - 1)

        while not index do
            buffer = file:read(buffer_size)
            index = buffer:find(separator[entities])
            raw_item = raw_item .. buffer:sub(1, index)
        end
        file_position = file_position + raw_item:len()
        _G['migrate_' .. entities:sub(1, -2)](raw_item)
    end
    print('all done')
end

function migrate_user(raw_user)
    local fields = {}
    local i = 1
    raw_user:gsub("([^".. "\1" .."]*)" .. "\1", function (field)
        fields[i] = field
        i = i + 1
    end)

    print('migrating user ' .. fields[2])
    print(db:query("insert into users (created, username, salt, password, email, isadmin) values (" ..
        db:escape_literal(fields[8]) .. ", " ..
        db:escape_literal(fields[2]) .. ", " ..
        db:escape_literal(fields[5]) .. ", " ..
        db:escape_literal(fields[4]) .. ", " ..
        db:escape_literal(fields[3]) .. ", " ..
        "false);"))
end

function migrate_project(raw_project)
    local fields = {}
    local i = 1
    raw_project:gsub("([^".. "\2" .."]*)" .. "\2", function (field)
        fields[i] = field
        i = i + 1
    end)

    -- print('migrating project ' .. fields[1])
    
    local result, err = db:query("insert into projects (projectname, username, ispublic, ispublished, created, lastupdated, lastshared) values (" ..
        db:escape_literal(fields[1]) .. ", " ..
        db:escape_literal(fields[2]) .. ", " ..
        db:escape_literal(fields[3]) .. ", false, " ..
        db:escape_literal(fields[4]) .. ", " ..
        db:escape_literal(fields[4]) .. ", " ..
        ((fields[3] == "true") and (db:escape_literal(fields[4])) or "NULL") ..
        ") on conflict(projectname, username) do update set projectname = excluded.projectname, username = excluded.username returning id;"
    )

    if (result) then
        saveToDisk(result[1].id, 'project.xml', fields[6])
        if (not generate_thumbnail(result[1].id)) then
            local log = io.open('/tmp/import.log', 'a')
            log:write(raw_project)
            log:close()
        end
        -- We need to find the media XML from the media file. We could probably just
        -- concatenate it into the project XML and forget about this extra file, or
        -- import all media altogether later
    --    saveToDisk(project.id, 'media.xml', get_media(fields[1], fields[2])) 
    else
        print(err)
        os.exit()
    end
end

function migrate_media(raw_media)
    local fields = {}
    local i = 1
    raw_media:gsub("([^".. "\2" .."]*)" .. "\2", function (field)
        fields[i] = field
        i = i + 1
    end)

    -- print('migrating media for ' .. fields[1])
    
    local result, err = db:query("select id from projects where projectname = " ..
        db:escape_literal(fields[1]) .. 
        ' and username = ' .. db:escape_literal(fields[2]) .. ';'
    )

    if (result) then
        saveToDisk(result[1].id, 'media.xml', fields[5])
    else
        print(err)
        os.exit()
    end
end


function generate_thumbnail(id)
    local project_file = io.open(directoryForId(id) .. '/project.xml')
    if (project_file) then
        local project = xml.load(project_file:read('*all'))
        project_file:close()
        saveToDisk(id, 'thumbnail', xml.find(project, 'thumbnail')[1])
        return true
    else
        return false
    end
end

-- Benchmarking buffer sizes
--[[
local command = io.popen('date +%s%N')
local time = tonumber(command:read('*all'))
command:close()
]]
_G['migrate_collection'](table)
--[[local command = io.popen('date +%s%N')
print(tonumber(command:read('*all')) - time)
command:close()
]]