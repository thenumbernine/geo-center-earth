#!/usr/bin/env luajit
local table = require 'ext.table'
local tolua = require 'ext.tolua'
local path = require 'ext.path'
local json = require 'dkjson'
local gl = require 'gl'
local glcall = require 'gl.call'
local glu = require 'ffi.req' 'glu'
local ffi = require 'ffi'
local ig = require 'imgui'
local matrix = require 'matrix'

--local boundaries = assert(json.decode(path'tectonicplates/GeoJSON/PB2002_boundaries.json':read()))
--local orogens = assert(json.decode(path'tectonicplates/GeoJSON/PB2002_orogens.json':read()))
--local steps = assert(json.decode(path'tectonicplates/GeoJSON/PB2002_steps.json':read()))

local App = require 'imguiapp.withorbit'()
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
	{name='plates', data=assert(json.decode(assert(path'tectonicplates/GeoJSON/PB2002_plates.json':read())))},
	--{name='steps', data=steps},
	--{name='coastline', data=assert(json.decode(path'naturalearthdata/ne_10m_coastline.geojson':read()))},
	--{name='land', data=assert(json.decode(path'naturalearthdata/ne_10m_land.geojson':read()))},
}

local equatorialRadius = 1
-- [[ Earth
local inverseFlattening = 298.257223563
local eccentricitySquared = (2 * inverseFlattening - 1) / (inverseFlattening * inverseFlattening)
--]]
--[[ perfect sphere
local eccentricitySquared = 0
--]]

local function calc_N(sinTheta, equatorialRadius, eccentricitySquared)
	local denom = math.sqrt(1 - eccentricitySquared * sinTheta * sinTheta)
	return equatorialRadius / denom
end

local function calc_dN_dTheta(sinTheta, cosTheta, equatorialRadius, eccentricitySquared)
	local denom = math.sqrt(1 - eccentricitySquared * sinTheta * sinTheta)
	return eccentricitySquared * sinTheta * cosTheta * equatorialRadius / (denom * denom * denom)
end

-- |d(x,y,z)/d(h,theta,phi)| for h=0
local function dx_dsphere_det_h_eq_0(lon, lat) 
	local phi = math.rad(lon)
	local theta = math.rad(lat)
	local sinTheta = math.sin(theta)
	local cosTheta = math.cos(theta)
	
	local h = 0
	local N = calc_N(sinTheta, equatorialRadius, eccentricitySquared)
	local dN_dTheta = calc_dN_dTheta(sinTheta, cosTheta, equatorialRadius, eccentricitySquared)
	local cosTheta2 = cosTheta * cosTheta
	return N * (
		N * cosTheta 
		+ eccentricitySquared * cosTheta2 * N * cosTheta
		+ eccentricitySquared * cosTheta2 * dN_dTheta * sinTheta
	)
end


--[[
only good for eccentricity = 0
so N = equatorialRadius
where
a_theta = a in latitude
b_theta = b in latitude
c_theta = c in latitude

expr: integrate(integrate(N^2 * cos(a_theta + (b_theta-a_theta) * u + (c_theta-a_theta) * v), v, 0, 1-u), u, 0, 1)
...where |d(xyz)/d(h,theta,theta)| = N^2 cos(theta) = N^2 cos(a_theta + (b_theta-a_theta)*u + (c_theta-a_theta)*v)
... gives this:
--]]
local function perfectSphere_triArea(a_lat, b_lat, c_lat)
	local a_theta = math.rad(a_lat)
	local b_theta = math.rad(b_lat)
	local c_theta = math.rad(c_lat)
	local ca_theta = c_theta - a_theta
	local ba_theta = b_theta - a_theta 
	local cb_theta = c_theta - b_theta
	return equatorialRadius * equatorialRadius * (
		  math.cos(b_theta) * ca_theta
		- math.cos(a_theta) * cb_theta
		- math.cos(c_theta) * ba_theta
	) / (ba_theta * ca_theta * cb_theta)
end

--[[
triCOM = same integral as above but times (x,y,z)
...where...
x = R * cos(theta) * cos(phi)
y = R * cos(theta) * sin(phi)
z = R * sin(theta)
theta = a_theta + (b_theta - a_theta)*u + (c_theta - a_theta)*v
phi = a_phi + (b_phi - a_phi)*u + (c_phi - a_phi)*v
... and this is stalling out every CAS I put it through.
To do this by hand: do a change-of-basis, but that means exchanging the boundaries for a linear function of u's and v's, and chopping the integral up into 2 based on the triangle's alignment with lat & lon
--]]
local function convertLatLonToSpheroid3D(lon, lat)
	local phi = math.rad(lon)
	local theta = math.rad(lat)
	local cosTheta = math.cos(theta)
	local sinTheta = math.sin(theta)
	
	local N = calc_N(sinTheta, equatorialRadius, eccentricitySquared)
	
	local height = 0
	local NPlusH = N + height
	return 
		NPlusH * cosTheta * math.cos(phi),
		NPlusH * cosTheta * math.sin(phi),
		(N * (1 - eccentricitySquared) + height) * sinTheta
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
	local theta = math.atan2(z, r2);

	-- lon, lat:
	return math.deg(theta), math.deg(phi)
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
		--[[ analytical expression for sphere triangle surface integral xform:
		local dsphere_dlatlon = .5 * matrix{a,b}:det()
		local triarea = perfectSphere_triArea(0, a[2], b[2]) * dsphere_dlatlon
		local tricom = perfectSphere_triCOM(0, a[2], b[2]) * dsphere_dlatlon
		--]]
		--[[ analytical expression for spheroid centroid triangle surface integral / average in xyz after projection to spheroid
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
print(feature.geometry.type)		
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
_G.drawSolid = false
_G.useGLUForPoly = false

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
		if useGLUForPoly then
			-- glu tess stuff here
			if not poly.callID then	
				poly.callID = gl.glGenLists(1)
				assert(poly.callID ~= 0)
				tess = glu.gluNewTess()
				assert(tess ~= nil)

				glu.gluTessCallback(tess, glu.GLU_TESS_BEGIN, ffi.cast('GLvoid(*)()', gl.glBegin))
				glu.gluTessCallback(tess, glu.GLU_TESS_END, gl.glEnd)
				glu.gluTessCallback(tess, glu.GLU_TESS_ERROR, ffi.cast('GLvoid(*)()', function(code) error(ffi.string(glu.gluErrorString(code))) end))
				glu.gluTessCallback(tess, glu.GLU_TESS_VERTEX, ffi.cast('GLvoid(*)()', gl.glVertex3dv))
		
				-- [[ crashes ... but won't draw without this ...
				-- why does tesselation/src/main.cpp write out data when it never uses it?
				local vertices = table()
				glu.gluTessCallback(tess, glu.GLU_TESS_COMBINE, function(newVertex, neighborVertex, neighborWeight, outData)
					local vertex = ffi.new('double[3]')
					--ffi.copy(vertex, newVertex, ffi.sizeof'double[3]')
					vertex[0] = newVertex[0]
					vertex[1] = newVertex[1]
					vertex[2] = newVertex[2]
					outData[0] = vertex
					vertices:insert(vertex)
				end)
				--]]

				gl.glNewList(poly.callID, gl.GL_COMPILE)
				gl.glColor3f(1,1,1)
				glu.gluTessBeginPolygon(tess, nil)
				glu.gluTessBeginContour(tess)
				
				for _,coord in ipairs(poly) do
					local xyz = ffi.new('GLdouble[3]')
					if drawOnSphere then
						local x,y,z = convertLatLonToSpheroid3D(table.unpack(coord))
						xyz[0] = x
						xyz[1] = y
						xyz[2] = z
					else
						xyz[0] = coord[1]
						xyz[1] = coord[2]
						xyz[2] = 0
					end
					glu.gluTessVertex(tess, xyz, xyz)
				end
				gl.glEndList()

				glu.gluTessEndContour(tess)
				glu.gluTessEndPolygon(tess)
				glu.gluDeleteTess(tess)
			else
				gl.glCallList(poly.callID)
			end
		else
			-- hmm not working... hitting a vertex limit?
			gl.glBegin(gl.GL_POLYGON)
			--gl.glBegin(gl.GL_TRIANGLE_FAN)
			for _,coord in ipairs(poly) do
				if drawOnSphere then
					gl.glVertex3d(convertLatLonToSpheroid3D(table.unpack(coord)))
				else
					gl.glVertex3d(coord[1], coord[2], 0)
				end
			end
			gl.glEnd()
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
	
	-- todo invalidate this if anything changes
	self.drawList = self.drawList or {}
	glcall(self.drawList, function()
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
	end)
	
	App.super.update(self, ...)
end

function App:updateGUI(...)
	if ig.luatableCheckbox('drawOnSphere', _G, 'drawOnSphere') then
		self.drawList = {}
	end
	ig.luatableCheckbox('drawCOMs', _G, 'drawCOMs')
	ig.luatableCheckbox('drawSolid', _G, 'drawSolid')
	
	self.view.ortho = not drawOnSphere
	
	for _,layer in ipairs(layers) do
		local com = layer.com
		local mass = layer.mass
		layer.disabled = not not layer.disabled
		ig.igPushID_Str(layer.name)
		ig.igText(layer.name..' area '..mass)
		ig.igSameLine()
		if ig.igCollapsingHeader'' then
			for _,k in ipairs{'disabled'} do
				ig.luatableCheckbox(k, layer, k)
			end
		end
		ig.igPopID()
	end
end

print('lat', latmin, latmax)
print('lon', lonmin, lonmax)

return App():run()
