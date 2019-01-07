#!/usr/bin/env luajit
require 'ext'
local ImGuiApp = require 'imguiapp'
local json = require 'dkjson'
local gl = require 'gl'
local ffi = require 'ffi'
local ig = require 'ffi.imgui'
local matrix = require 'matrix'

--local boundaries = assert(json.decode(file['tectonicplates/GeoJSON/PB2002_boundaries.json']))
--local orogens = assert(json.decode(file['tectonicplates/GeoJSON/PB2002_orogens.json']))
--local plates = assert(json.decode(file['tectonicplates/GeoJSON/PB2002_plates.json']))
--local steps = assert(json.decode(file['tectonicplates/GeoJSON/PB2002_steps.json']))
--local coastline = assert(json.decode(file['naturalearthdata/ne_10m_coastline.geojson']))
local land = assert(json.decode(file['naturalearthdata/ne_10m_land.geojson']))

local Orbit = require 'glapp.orbit'
local View = require 'glapp.view'
local App = class(Orbit(View.apply(ImGuiApp)))
App.title = 'Geo Center'

function App:initGL(...)
	App.super.initGL(self, ...)
	gl.glEnable(gl.GL_DEPTH_TEST)

	self.view.zNear = 1
	self.view.zFar = 10000
	self.view.ortho = true
end

local layers = {
	--{name='boundaries', data=boundaries, color={1,0,0}},
	--{name='orogens', data=orogens, color={1,1,0}},
	--{name='plates', data=plates, color={0,1,0}},
	--{name='steps', data=steps, color={0,1,1}},
	--{name='coastline', data=coastline, color={0,1,1}},
	{name='land', data=land, color={0,1,1}},
}

function App:update(...)
	gl.glClear(bit.bor(gl.GL_COLOR_BUFFER_BIT, gl.GL_DEPTH_BUFFER_BIT))

	for _,layer in ipairs(layers) do
		if not layer.disabled then		
			for _,feature in ipairs(layer.data.features) do
				if not feature.disabled then
					
					if not feature.color then
						feature.color = matrix{math.random(), math.random(), math.random()}
						feature.color = feature.color / feature.color:norm()
					end	
					gl.glColor3f(table.unpack(feature.color))

					local polygon = gl.GL_POLYGON
					if feature.gl_drawlines then
						polygon = gl.GL_LINE_LOOP
					end
	
					if feature.geometry.type == 'LineString' then
						gl.glBegin(gl.GL_LINE_STRIP)
						for _,coord in ipairs(feature.geometry.coordinates) do
							gl.glVertex2f(coord[1], coord[2])
						end
						gl.glEnd()	
					elseif feature.geometry.type == 'Polygon' then
						for _,poly in ipairs(feature.geometry.coordinates) do
							gl.glBegin(polygon)
							for _,coord in ipairs(poly) do
								gl.glVertex2f(coord[1], coord[2])
							end
							gl.glEnd()	
						end
					elseif feature.geometry.type == 'MultiPolygon' then
						for _,group in ipairs(feature.geometry.coordinates) do
							for _,poly in ipairs(group) do
								gl.glBegin(polygon)
								for _,coord in ipairs(poly) do
									gl.glVertex2f(coord[1], coord[2])
								end
								gl.glEnd()	
							end		
						end		
					else
						error("unknown geometry.type "..feature.geometry.type)
					end
				end
			end
		end
	end
	
	App.super.update(self, ...)
end

local bool = ffi.new('bool[1]')
local function checkbox(t, k)
	bool[0] = not not t[k]
	if ig.igCheckbox(k, bool) then
		t[k] = not not bool[0]
	end
end

function App:updateGUI(...)
	for _,layer in ipairs(layers) do
		ig.igPushIDStr(layer.name)
		ig.igText(layer.name)
		for _,k in ipairs{'disabled'} do
			checkbox(layer, k)
		end
		
		for _,feature in ipairs(layer.data.features) do
			for _,k in ipairs{'disabled', 'gl_drawlines'} do
				checkbox(feature, k)
			end
		end
		
		ig.igPopID()
	end
end

App():run()
