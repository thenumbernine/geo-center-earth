#!/usr/bin/env luajit
require 'ext'
local ImGuiApp = require 'imguiapp'
local json = require 'dkjson'
local gl = require 'gl'
local glu = require 'ffi.glu'
local ffi = require 'ffi'
local ig = require 'ffi.imgui'
local matrix = require 'matrix'

--local boundaries = assert(json.decode(file['tectonicplates/GeoJSON/PB2002_boundaries.json']))
--local orogens = assert(json.decode(file['tectonicplates/GeoJSON/PB2002_orogens.json']))
--local steps = assert(json.decode(file['tectonicplates/GeoJSON/PB2002_steps.json']))

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
	--{name='coastline', data=assert(json.decode(file['naturalearthdata/ne_10m_coastline.geojson']))},
	{name='land', data=assert(json.decode(file['naturalearthdata/ne_10m_land.geojson']))},
}

local equatorialRadius = 1
-- [[ Earth
local inverseFlattening = 298.257223563
local eccentricitySquared = (2 * inverseFlattening - 1) / (inverseFlattening * inverseFlattening)
--]]
--[[ perfect sphere
local eccentricitySquared = 0
--]]

local function calc_N(sinPhi, equatorialRadius, eccentricitySquared)
	local denom = math.sqrt(1 - eccentricitySquared * sinPhi * sinPhi)
	return equatorialRadius / denom
end

local function calc_dN_dphi(sinPhi, cosPhi, equatorialRadius, eccentricitySquared)
	local denom = math.sqrt(1 - eccentricitySquared * sinPhi * sinPhi)
	return eccentricitySquared * sinPhi * cosPhi * equatorialRadius / (denom * denom * denom)
end

-- |d(x,y,z)/d(h,lambda,phi)| for h=0
local function dx_dsphere_det_h_eq_0(lon, lat) 
	local phi = math.rad(lat)
	local lambda = math.rad(lon)
	local sinPhi = math.sin(phi)
	local cosPhi = math.cos(phi)
	
	local h = 0
	local N = calc_N(sinPhi, equatorialRadius, eccentricitySquared)
	local dN_dphi = calc_dN_dphi(sinPhi, cosPhi, equatorialRadius, eccentricitySquared)
	local cosPhi2 = cosPhi * cosPhi
	return N * (
		N * cosPhi 
		+ eccentricitySquared * cosPhi2 * N * cosPhi
		+ eccentricitySquared * cosPhi2 * dN_dphi * sinPhi
	)
end


--[[
only good for eccentricity = 0
so N = equatorialRadius
where
a_phi = a in latitude
b_phi = b in latitude
c_phi = c in latitude

expr: integrate(integrate(N^2 * cos(a_phi + (b_phi-a_phi) * u + (c_phi-a_phi) * v), v, 0, 1-u), u, 0, 1)
...where |d(xyz)/d(h,phi,lambda)| = N^2 cos(phi) = N^2 cos(a_phi + (b_phi-a_phi)*u + (c_phi-a_phi)*v)
... gives this:
--]]
local function perfectSphere_triArea(a_lat, b_lat, c_lat)
	local a_phi = math.rad(a_lat)
	local b_phi = math.rad(b_lat)
	local c_phi = math.rad(c_lat)
	local ca_phi = c_phi - a_phi
	local ba_phi = b_phi - a_phi 
	local cb_phi = c_phi - b_phi
	return equatorialRadius * equatorialRadius * (
		  math.cos(b_phi) * ca_phi
		- math.cos(a_phi) * cb_phi
		- math.cos(c_phi) * ba_phi
	) / (ba_phi * ca_phi * cb_phi)
end

--[[
triCOM = same integral as above but times (x,y,z)
...where...
x = R * cos(phi) * cos(lambda)
y = R * cos(phi) * sin(lambda)
z = R * sin(phi)
phi = a_phi + (b_phi - a_phi)*u + (c_phi - a_phi)*v
lambda = a_lambda + (b_lambda - a_lambda)*u + (c_lambda - a_lambda)*v
...so the integral looks like:
integrate(integrate(R^3 * cos(a + (b-a) * u + (c-a) * v)^2 * cos(d + (e-d) * u + (f-d) * v), v, 0, 1-u), u, 0, 1)
... and this is stalling out every CAS I put it through.
To do this by hand: do a change-of-basis, but that means exchanging the boundaries for a linear function of u's and v's, and chopping the integral up into 2 based on the triangle's alignment with lat & lon
--]]

local function convertLatLonToSpheroid3D(lon, lat)
	local phi = math.rad(lat)
	local lambda = math.rad(lon)
	local cosPhi = math.cos(phi)
	local sinPhi = math.sin(phi)
	local sinPhiSquared = sinPhi * sinPhi
	
	local N = equatorialRadius / math.sqrt(1 - eccentricitySquared * sinPhiSquared)
	
	local height = 0
	local NPlusH = N + height
	return 
		NPlusH * cosPhi * math.cos(lambda),
		NPlusH * cosPhi * math.sin(lambda),
		(N * (1 - eccentricitySquared) + height) * sinPhi
end

local function convertSpheroid3DToLatLon(x,y,z)
	-- this much is always true
	local phi = math.atan2(y, x);

--[[ radial distance for spheroid:
r = (N+h)^2 + ( N eps^2 - 2 (N+h) ) N eps^2 sin(phi)^2
phi = atan2(...) 
r[0] = (x^2 + y^2 + z^2)^.5
phi[0] = atan2(z, (x^2 + y^2)^.5)
--]]

	-- spherical:
	local r2 = math.sqrt(x*x + y*y);
	local r = math.sqrt(r2*r2 + z*z);
	local lambda = math.atan2(z, r2);

	-- lon, lat:
	return math.deg(lambda), math.deg(phi)
end


local function cross(a,b)
	return matrix{ 
		a[2] * b[3] - a[3] * b[2],
		a[3] * b[1] - a[1] * b[3],
		a[1] * b[2] - a[2] * b[1],
	}
end

local function calcFeatureCOM(poly)
	local com
	local area = 0
	local n = #poly
	assert(n > 2)
	for i=1,n do
		local i2 = i % n + 1
		
		local a = matrix(poly[i])
		local b = matrix(poly[i2])
	
		-- [[ cartesian centroid / average in lat/lon space
		local triarea = .5 * matrix{a,b}:det()
		local tricom = (a + b) / 3
		--]]
		--[[ cartesian centroid in xyz space ... 3rd vertex is always origin, so it is biased ...
		local carta = matrix{convertLatLonToSpheroid3D(table.unpack(a))}
		local cartb = matrix{convertLatLonToSpheroid3D(table.unpack(b))}
		local triarea = .5 * cross(carta, cartb):norm()
		local tricom = (carta + cartb) / 3
		--]]
		--[[ perfect sphere triangle surface integral xform:
		local dsphere_dlatlon = .5 * matrix{a,b}:det()
		local triarea = perfectSphere_triArea(0, a[2], b[2]) * dsphere_dlatlon
		local tricom = perfectSphere_triCOM(0, a[2], b[2]) * dsphere_dlatlon
		--]]
		--[[ spheroid centroid triangle surface integral / average in xyz after projection to spheroid
		local dsphere_dlatlon = .5 * matrix{a,b}:det()
		local triarea = dsphere_dlatlon * dx_dsphere_det_h_eq_0(table.unpack(coord))
		--]]
		com = com and (com + tricom * triarea) or (tricom * triarea)
		area = area + triarea
	end
	com = com / area
	return com, area
end

for _,layer in ipairs(layers) do
	local com
	local mass = 0
	for _,feature in ipairs(layer.data.features) do
		local fcom
		local fmass = 0
		if feature.geometry.type == 'LineString' then
			fcom, fmass = calcFeatureCOM(feature.geometry.coordinates)
		elseif feature.geometry.type == 'Polygon' then
			for _,poly in ipairs(feature.geometry.coordinates) do
				local pcom, pmass = calcFeatureCOM(poly)
				poly.com = pcom
				poly.mass = pmass
				fcom = fcom and (fcom + pcom * pmass) or (pcom * pmass)
				fmass = fmass + pmass
			end
			fcom = fcom / fmass
		elseif feature.geometry.type == 'MultiPolygon' then
			for _,group in ipairs(feature.geometry.coordinates) do
				for _,poly in ipairs(group) do
					local pcom, pmass = calcFeatureCOM(poly)
					poly.com = pcom
					poly.mass = pmass
					fcom = fcom and (fcom + pcom * pmass) or (pcom * pmass)
					fmass = mass + pmass
				end
			end
			fcom = fcom / fmass
		else
			error('here')
		end
		feature.com = fcom
		feature.mass = fmass
		com = com and (com + fcom * fmass) or (fcom * fmass)
		mass = mass + fmass
	end
	com = com / mass
	layer.com = com
	layer.mass = mass
	local com_2D = #com == 3 and matrix{convertSpheroid3DToLatLon(com:unpack())} or nil
	print(tolua{
		name=layer.name,
		com_3D=layer.com,
		com_2D=com_2D,
		mass=layer.mass,
	})
end

_G.drawOnSphere = false
_G.drawCOMs = false

local function vertex(coord)
	if drawOnSphere then
		gl.glVertex3f(convertLatLonToSpheroid3D(table.unpack(coord)))
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

	if drawSolid then
		-- glu tess stuff here
		if not tess then
			local xyz = ffi.new('GLdouble[3]')
			tess = glu.gluNewTess()
			
			glu.gluTessBeginPolygon(tess, userdata)
			glu.gluTessBeginContour(tess)	-- or gluTessBeginPolygon() ?
			if drawOnSphere then
			else
				xyz[0] = coord[1]
				xyz[1] = coord[2]
				xyz[2] = 0
			end
			
			glu.gluTessVertex(tess, xyz, vertexData)	-- what's the diff between xyz and vertexData?
			glu.gluTessEndContour(tess)
			glu.gluTessEndPolygon(tess, userdata)
		else
		end
	else
		gl.glBegin(gl.GL_LINE_LOOP)
		for _,coord in ipairs(poly) do
			local lon, lat = table.unpack(coord)
			latmin = math.min(latmin, lat)
			latmax = math.max(latmax, lat)
			lonmin = math.min(lonmin, lon)
			lonmax = math.max(lonmax, lon)

			vertex(coord)
		end
		gl.glEnd()	
	end

	if drawCOMs then
		assert(poly.com)
		if poly.com then
			gl.glBegin(gl.GL_LINES)
			--for _,coord in ipairs(poly) do
			local n = 5
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
