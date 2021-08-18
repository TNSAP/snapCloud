-- Community site module
-- =====================
--
-- Routes for all community website pages. We're in the process of starting to
-- transition the whole site to Lua.
--
-- Written by Bernat Romagosa and Michael Ball
--
-- Copyright (C) 2021 by Bernat Romagosa and Michael Ball
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

local app = package.loaded.app
local capture_errors = package.loaded.capture_errors
local respond_to = package.loaded.respond_to
local disk = package.loaded.disk

local Projects = package.loaded.Projects
local Collections = package.loaded.Collections
local db = package.loaded.db

app:enable('etlua')
app.layout = require 'views.layout'

local component = require 'component'

local views = {
    -- Static pages
    'about', 'bjc', 'coc', 'contact', 'credits', 'dmca', 'extensions',
    'materials', 'mirrors', 'offline', 'partners', 'privacy', 'requirements',
    'research', 'snapinator', 'snapp', 'source', 'tos',

    -- Simple pages
    'admin', 'blog', 'change_email', 'change_password', 'delete_user',
    'forgot_password', 'forgot_username', 'login', 'sign_up'
}

for _, view in pairs(views) do
    app:get('/' .. view, function (self)
        return { render = view }
    end)
end

app:get('/explore', function (self)
    self.Projects = Projects
    self.Collections = Collections
    self.db = db
    self.course_name_filter = course_name_filter
    self.new_component = component.new

    return {
        render = 'explore',
    }
end)

app:get('/my_projects', function (self)
    self.Projects = Projects
    self.username = self.session.username
    self.db = db
    self.new_component = component.new

    return {
        render = 'my_projects',
    }
end)

component.actions['grid'] = {
    first = function (data, _)
        data.page_number = 1
        component.actions['grid'].update_items(data)
    end,
    last = function (data, _)
        data.page_number = data.total_pages
        component.actions['grid'].update_items(data)
    end,
    next = function (data, params)
        data.page_number =
            math.min(data.total_pages, data.page_number + params[1])
        component.actions['grid'].update_items(data)
    end,
    previous = function (data, params)
        data.page_number = math.max(1, data.page_number - params[1])
        component.actions['grid'].update_items(data)
    end,
    search = function (data, params)
        data.search_term = params[1]
        if data.search_term then
            print('\n\n\nsearching: ' .. data.search_term .. '\n\n')
        end
        component.actions['grid'].update_items(data)
    end,
    update_items = function (data, _)
        component.actions['grid']['update_' .. data.item_type .. 's'](data)
    end,
    update_projects = function (data, _)
        local paginator =
            Projects:paginated(
                data.query ..
                    (data.search_term and (db.interpolate_query(
                        ' and (projectname ILIKE ? or notes ILIKE ?)',
                        data.search_term,
                        data.search_term)
                    ) or '') ..
                ' ORDER BY ' .. data.order,
            { per_page = 15 })

        data.items = paginator:get_page(data.page_number)
        disk:process_thumbnails(data.items)
    end,
    update_collections = function (data, _)
        local query =
            'JOIN active_users on ' ..
                '(active_users.id = collections.creator_id) ' ..
                'WHERE published ORDER BY collections.published_at DESC'

        local paginator = Collections:paginated(
            query,
            {
                per_page = 15,
                fields =
                    'collections.id, creator_id, collections.created_at, '..
                    'published, collections.published_at, shared, ' ..
                    'collections.shared_at, collections.updated_at, name, ' ..
                    'description, thumbnail_id, username, editor_ids'
            }
        )

        data.items = paginator:get_page(data.page_number)
        disk:process_thumbnails(data.items, 'thumbnail_id')
    end
}
