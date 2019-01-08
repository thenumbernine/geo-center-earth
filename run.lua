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
--local steps = assert(json.decode(file['tectonicplates/GeoJSON/PB2002_steps.json']))
--local coastline = assert(json.decode(file['naturalearthdata/ne_10m_coastline.geojson']))

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
	--{name='boundaries', data=boundaries},
	--{name='orogens', data=orogens},
	--{name='plates', data=assert(json.decode(file['tectonicplates/GeoJSON/PB2002_plates.json']))},
	--{name='steps', data=steps},
	--{name='coastline', data=coastline},
	{name='land', data=assert(json.decode(file['naturalearthdata/ne_10m_land.geojson']))},
}


local function calcFeatureCOM(poly)
	local com = matrix{0,0}
	local area = 0
	local n = #poly
	assert(n > 2)
	for i=1,n do
		local i2 = i % n + 1
		
		local a = matrix(poly[i])
		local b = matrix(poly[i2])
		local triarea = .5 * matrix{a,b}:det()
		com = com + (a + b) * triarea
		area = area + triarea
	end
	com = com / (3 * area)
	return com, area
end

for _,layer in ipairs(layers) do
	local com = matrix{0,0}
	local mass = 0
	for _,feature in ipairs(layer.data.features) do
		local fcom = matrix{0,0}
		local fmass = 0
		if feature.geometry.type == 'LineString' then
			fcom, fmass = calcFeatureCOM(feature.geometry.coordinates)
		elseif feature.geometry.type == 'Polygon' then
			for _,poly in ipairs(feature.geometry.coordinates) do
				local pcom, pmass = calcFeatureCOM(poly)
				poly.com = pcom
				poly.mass = pmass
				fcom = fcom + pcom * pmass
				fmass = fmass + pmass
			end
			fcom = fcom / fmass
		elseif feature.geometry.type == 'MultiPolygon' then
			for _,group in ipairs(feature.geometry.coordinates) do
				for _,poly in ipairs(group) do
					local pcom, pmass = calcFeatureCOM(poly)
					poly.com = pcom
					poly.mass = pmass
					fcom = fcom + pcom * pmass
					fmass = mass + pmass
				end
			end
			fcom = fcom / fmass
		else
			error('here')
		end
		feature.com = fcom
		feature.mass = fmass
		com = com + fcom * fmass
		mass = mass + fmass
	end
	com = com / mass
	layer.com = com
	layer.mass = mass
end

_G.drawOnSphere = false
_G.drawCOMs = false

local function spherexform(lon, lat)
	local inverseFlattening = 298.257223563
	local equatorialRadius = 1
	local height = 0

	local phi = math.rad(lat)
	local lambda = math.rad(lon)
	local cosPhi = math.cos(phi)
	local sinPhi = math.sin(phi)
	local eccentricitySquared = (2 * inverseFlattening - 1) / (inverseFlattening * inverseFlattening)
	local sinPhiSquared = sinPhi * sinPhi
	local N = equatorialRadius / math.sqrt(1 - eccentricitySquared * sinPhiSquared)
	local NPlusH = N + height
	return 
		NPlusH * cosPhi * math.cos(lambda),
		NPlusH * cosPhi * math.sin(lambda),
		(N * (1 - eccentricitySquared) + height) * sinPhi
end

local function vertex(coord)
	if drawOnSphere then
		gl.glVertex3f(spherexform(table.unpack(coord)))
	else
		gl.glVertex2f(coord[1], coord[2])
	end
end

local latmin = math.huge
local latmax = -math.huge
local lonmin = math.huge
local lonmax = -math.huge

local function drawPoly(poly)
	if not poly.color then
		poly.color = matrix{math.random(), math.random(), math.random()}
		poly.color = poly.color / poly.color:norm()
	end	
	gl.glColor3f(table.unpack(poly.color))						
	
	gl.glBegin(gl.GL_LINE_STRIP)
	for _,coord in ipairs(poly) do
		local lon, lat = table.unpack(coord)
		latmin = math.min(latmin, lat)
		latmax = math.max(latmax, lat)
		lonmin = math.min(lonmin, lon)
		lonmax = math.max(lonmax, lon)

		vertex(coord)
	end
	gl.glEnd()	

	if drawCOMs then
		assert(poly.com)
		if poly.com then
			gl.glBegin(gl.GL_LINES)
			--for _,coord in ipairs(poly) do
			local n = 30
			for i=1,n do
				local j = math.floor((i-1)/(n-1)*(#poly-1))+1
				local coord = poly[j]

				vertex(coord)
				gl.glVertex3f(poly.com[1] or 0, poly.com[2] or 0, poly.com[3] or 0)
			
			end
			gl.glEnd()
		end
	end
end

--layers[1].data.features = table.sub(layers[1].data.features, 1, 1)

function App:update(...)
	gl.glClear(bit.bor(gl.GL_COLOR_BUFFER_BIT, gl.GL_DEPTH_BUFFER_BIT))
	
	for _,layer in ipairs(layers) do
		if not layer.disabled then		
			for _,feature in ipairs(layer.data.features) do
				if feature.geometry.type == 'LineString' then
					drawPoly(feature.geometry.coordinates)
				elseif feature.geometry.type == 'Polygon' then
					assert(#feature.geometry.coordinates == 1)
					for _,poly in ipairs(feature.geometry.coordinates) do
						drawPoly(poly)
					end
				elseif feature.geometry.type == 'MultiPolygon' then
					for _,group in ipairs(feature.geometry.coordinates) do
						for _,poly in ipairs(group) do
							drawPoly(poly)
						end		
					end		
				else
					error("unknown geometry.type "..feature.geometry.type)
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
	checkbox(_G, 'drawOnSphere')
	checkbox(_G, 'drawCOMs')
	
	self.view.ortho = not drawOnSphere
	
	for _,layer in ipairs(layers) do
		local com = layer.com
		local mass = layer.mass
		ig.igPushIDStr(layer.name)
		ig.igText(layer.name..' area '..mass)
		ig.igSameLine()
		if ig.igCollapsingHeader'' then
			for _,k in ipairs{'disabled'} do
				checkbox(layer, k)
			end
		end
		ig.igPopID()
	end
end

App():run()

print('lat', latmin, latmax)
print('lon', lonmin, lonmax)
