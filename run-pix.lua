#!/usr/bin/env luajit
require 'ext'

--- BEGIN CUT FROM run.lua
-- GAAAHHH STANDARDS
-- physics spherical coordinates: the longitude is φ and the latitude (starting at the north pole and going down) is θ ...
-- mathematician spherical coordinates: the longitude is θ and the latitude is φ ...
-- geographic / map charts: the longitude is λ and the latitude is φ ...
-- so TODO change the calc_* stuff from r_theta_phi to h_phi_lambda ? idk ...

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
local function dx_dsphere_det_h_eq_0(lat) 
	local theta = math.rad(lat)
	local sinTheta = math.sin(theta)
	local cosTheta = math.cos(theta)
	
	local h = 0
	local N = calc_N(sinTheta, equatorialRadius, eccentricitySquared)
	local dN_dTheta = calc_dN_dTheta(sinTheta, cosTheta, equatorialRadius, eccentricitySquared)
	local cosTheta2 = cosTheta * cosTheta
	return -N * (
		N * cosTheta 
		+ eccentricitySquared * cosTheta2 * N * cosTheta
		+ eccentricitySquared * cosTheta2 * dN_dTheta * sinTheta
	)
end


-- lon and lat are in degrees
local function convertLatLonToSpheroid3D(lon, lat)
	local phi = math.rad(lon)		-- spherical phi
	local theta = math.rad(lat)		-- spherical theta
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

-- https://gis.stackexchange.com/questions/28446/computational-most-efficient-way-to-convert-cartesian-to-geodetic-coordinates
local function convertSpheroid3DToLatLon(x,y,z)
	-- [[
	-- this much is always true
	local phi = math.atan2(y, x);
	local theta
	for i=1,10000 do
		-- spherical:
		local r2 = math.sqrt(x*x + y*y);
		local newtheta = math.atan(r2 / z);
		if theta then
			local dtheta = math.abs(newtheta - theta)
			--print(dtheta, z)
			if dtheta < 1e-15 then break end
		end
		theta = newtheta
		x,y,z = convertLatLonToSpheroid3D( math.deg(phi), math.deg(theta) )
	end
	--]]
	--[[ sphere approx
	local phi = math.atan2(y, x)
	local theta = math.atan2(z, math.sqrt(x*x + y*y))
	--]]

	-- lon, lat:
	return (math.deg(phi) + 180) % 360 - 180, 
			--(math.deg(theta) + 90) % 180 - 90
			math.deg(theta)
end


--- END CUT FROM run.lua

-- [[
local Image = require 'image'
local img = Image'visibleearth/gebco_08_rev_bath_21600x10800.png'
assert(img)
local w, h, ch = img:size()
assert(ch == 1)
print('width', w, 'height', h)
--]]
--[[
local w, h = 200, 100
--]]
	
local continentImg = Image'continent-mask.png'
print('continent width', continentImg.width, 'height', continentImg.height, 'channels', continentImg.channels)
assert(continentImg.channels >= 3)
assert(continentImg.width == img.width)
assert(continentImg.height == img.height)

local comForMask = {}
local comLatLonForMask = {}
local areaForMask = {}

local matrix = require 'matrix'
local com = matrix{0,0,0}
local mass = 0

--[[
local com = matrix{0.6047097872861, 0.35902954396197, 0.7109316842868}
print('com',com)
print('lon lat of com',convertSpheroid3DToLatLon(com:unpack()))
--os.exit()
--]]


-- [=[
local lastTime = os.time()
local imgsize = w * h

local err_lon = 0
local err_lat = 0

local landArea = 0
local totalArea = 0
local e = 0
local hist = range(0,255):map(function(i) return 0, i end)
local step = 600
local max_err_lat  = 0
for j=0,h-1,step do
	local lat = (.5 - (j+.5)/h) * 180
	--local dA = math.abs(dx_dsphere_det_h_eq_0(lat)) * (2 * math.pi) / w * math.pi / h
	local dtheta = (math.pi * step) / h
	local dphi = (2 * math.pi * step) / w
	local sintheta = math.sin((j+.5) / h * math.pi)
	local dA = sintheta * dphi * dtheta 
	--assert(math.isfinite(dA))
	for i=0,w-1,step do
		e = i + w * j
		local lon = ((i+.5)/w - .5) * 360
		local v = img and img.buffer[e] 
	
		if img == nil or v >= 255 then
			-- consider this coordinate for land sum
			
			local pt = matrix{convertLatLonToSpheroid3D(lon, lat)}
			--assert(math.isfinite(pt[1]))
			--assert(math.isfinite(pt[2]))
			--assert(math.isfinite(pt[3]))
			-- [[ verify accuracy
			local lon2, lat2 = convertSpheroid3DToLatLon(pt:unpack())
--if i == 0 then print('lat ' .. lat .. ' lat2 ' .. lat2) end
			err_lon = err_lon + math.abs(lon-lon2) 
			local this_err_lat = math.abs(lat-lat2)
			max_err_lat = math.max(max_err_lat, this_err_lat)
			err_lat = err_lat + this_err_lat 
-- max err can get significant and that leads to a significant total error
--print(math.abs(lat-lat2))
			--]]
		
			com = com + pt * dA
			landArea = landArea + dA
			
			if continentImg then
				local cch = continentImg.channels
				-- or how about %02x ?
				local mask = tonumber(bit.bor(
					continentImg.buffer[0+cch*e],
					bit.lshift(continentImg.buffer[1+cch*e], 8),
					bit.lshift(continentImg.buffer[2+cch*e], 16)))
				
				comForMask[mask] = (comForMask[mask] or matrix{0,0,0}) + pt * dA
				areaForMask[mask] = (areaForMask[mask] or 0) + dA
			end
		end
		totalArea = totalArea + dA
	end
	local thisTime = os.time()
	if thisTime ~= lastTime then
		lastTime = thisTime
		print((100*e/imgsize)..'% complete')
		print('com', com)
		print('landArea', landArea)
	end
end
print('reconstruction lat error', err_lat)
print('reconstruction lon error', err_lon)
print('max lat error', max_err_lat) 
print('landArea', landArea)
print('totalArea', totalArea)
print('totalArea / 4pi', totalArea / (4 * math.pi))
print('% of earth covered by land =', (landArea / totalArea) * 100)
print('% of earth covered by water =', (1 - landArea / totalArea) * 100)
local comNorm = com:norm()
print('com norm', comNorm)
local com2 = com / comNorm 
print('com = ', com)
print('com2 = ', com2)
local latLon = matrix{convertSpheroid3DToLatLon(com2:unpack())}
print('com lon lat =', latLon) 
--]=]

for _,mask in ipairs(table.keys(comForMask)) do
	comForMask[mask] = comForMask[mask] / areaForMask[mask]
	print('mask', ('%x'):format(mask), 'com', comForMask[mask])
	comLatLonForMask[mask] = matrix{convertSpheroid3DToLatLon(comForMask[mask]:unpack())}
end

--[[
from a perfect sphere:
% of earth covered by water =	0.30733934311945
com norm	1.2923949574677
com = 	[0.60312270879214, 0.35783092714561, 0.71288149486247]
com lon lat =	[30.68053125546, 45.469847928957]

with flattening:
landArea	3.8880860100431
totalArea	12.650758716454
totalArea / 4pi	1.0067153917933
% of earth covered by water =	0.3073401443493
com norm	1.2981214018785
com = 	[0.6047097872861, 0.35902954396197, 0.7109316842868]
com lon lat =	[30.698539186783, 45.310770365875]
--]]


local gl = require 'gl'
local ig = require 'imgui'
local GLTex2D = require 'gl.tex2d'
local GLProgram = require 'gl.program'
local App = require 'imguiapp.withorbit'()
App.title = 'Geo Center'

function App:initGL(...)
	App.super.initGL(self, ...)
	gl.glEnable(gl.GL_DEPTH_TEST)

	local img = img:resize(2048,1024):rgb()
	print(img.width, img.height)
	self.tex = GLTex2D{
		-- [[
		image = img,
		--]]
		--[[
		width = img.width,
		height = img.height,
		data = img.buffer,
		internalFormat = gl.GL_LUMINANCE,
		format = gl.GL_LUMINANCE,
		type = gl.GL_UNSIGNED_BYTE,
		--]]	
		minFilter = gl.GL_LINEAR,
		magFilter = gl.GL_LINEAR,
		generateMipmap = true,
	}

	local continentImg = continentImg:resize(2048,1024):rgb():setChannels(4)
	for i=3,continentImg.width*continentImg.height*4,4 do
		continentImg.buffer[i] = 127
	end
	self.continentTex = GLTex2D{
		image = continentImg,
		minFilter = gl.GL_LINEAR,
		magFilter = gl.GL_LINEAR,
		generateMipmap = true,
	}

	self.shader = GLProgram{
		vertexCode = [[
varying vec3 color;
varying vec2 tc;
void main() {
	gl_Position = ftransform();
	color = gl_Color.rgb;
	tc = gl_MultiTexCoord0.st;
}
]],
		fragmentCode = [[
uniform sampler2D tex;
uniform sampler2D continents;
varying vec3 color;
varying vec2 tc;
void main() {
	gl_FragColor = mix(
		texture2D(tex, tc),
		texture2D(continents, tc),
		.5);
}
]],
		uniforms = {
			tex = 0,
			continents = 1,
		},
	}
end

-- globals for gui access
idivs = 100
jdivs = 100
normalizeWeights = true
sphereCoeff = 0
cylCoeff = 0
equirectCoeff = 0
aziequiCoeff = 0
mollweideCoeff = 0

-- TODO change this to (lat, lon, height)
-- bleh conventions:
--  physicist spherical: azimuthal = theta, lon = phi
--  mathematician spherical: azimuthal = phi, lon = theta
--  geographer: latitude = phi, lon = lambda
-- rather than pick one im just gonna say 'azimuthal, latitude, longitude'
-- oh and unitLonFrac is gonna be from 0=america to 1=east asia, so unitLonFrac==.5 means lon==0
local function vertex(aziFrac, unitLonFrac, height)
	local azimuthal = aziFrac * math.pi-- azimuthal angle
	local lat = .5*math.pi - azimuthal	-- latitude
	local lonFrac = unitLonFrac - .5
	local lon = lonFrac * math.pi * 2			-- longitude
	local cosaz, sinaz = math.cos(azimuthal), math.sin(azimuthal)
	local coslon, sinlon = math.cos(lon), math.sin(lon)
	
	local wgs84_a = 6378.137

	gl.glTexCoord2d(unitLonFrac, aziFrac)

	-- spherical coordinates
	local spherex = sinaz * coslon
	local spherey = sinaz * sinlon
	local spherez = cosaz
	-- rotate back so y is up
	spherey, spherez = spherez, -spherey
	-- now rotate so prime meridian is along -z instead of +x
	spherex, spherez = -spherez, spherex

	-- cylindrical
	local cylx = coslon
	local cyly = sinlon
	local cylz = lat
	-- rotate back so y is up
	cyly, cylz = cylz, -cyly
	-- now rotate so prime meridian is along -z instead of +x
	cylx, cylz = -cylz, cylx

	-- equirectangular
	local equirectx, equirecty, equirectz
	do
		local lambda = lon
		local phi = lat
		local R = 2/math.pi
		local lambda0 = 0
		local phi0 = 0
		local phi1 = 0
		equirectx, equirecty, equirectz = 
			R * (lambda - lambda0) * math.cos(phi1),
			R * (phi - phi0),
			height / wgs84_a
	end

	-- azimuthal equidistant
	local aziequix, aziequiy, aziequiz =
		math.cos(lon) * azimuthal,
		math.sin(lon) * azimuthal,
		height / wgs84_a
	-- swap +x to -y
	aziequix, aziequiy = aziequiy, -aziequix

	local mollweidex, mollweidey, mollweidez
	do
		local R = math.pi / 4
		local lambda = lon
		local lambda0 = 0	-- in degrees
		local phi = lat
		local theta
		if phi == .5 * math.pi then
			theta = .5 * math.pi
		else
			theta = phi
			for i=1,10 do
				local dtheta = (2 * theta + math.sin(2 * theta) - math.pi * math.sin(phi)) / (2 + 2 * math.cos(theta))
				if math.abs(dtheta) < 1e-5 then break end
				theta = theta - dtheta
			end
		end
		mollweidex = R * math.sqrt(8) / math.pi * (lambda - lambda0) * math.cos(theta)
		mollweidey = R * math.sqrt(2) * math.sin(theta)
		mollweidez = height / wgs84_a
		if not math.isfinite(mollweidex) then mollweidex = 0 end
		if not math.isfinite(mollweidey) then mollweidey = 0 end
		if not math.isfinite(mollweidez) then mollweidez = 0 end
	end

	local x = sphereCoeff * spherex + cylCoeff * cylx + equirectCoeff * equirectx + aziequiCoeff * aziequix + mollweideCoeff * mollweidex
	local y = sphereCoeff * spherey + cylCoeff * cyly + equirectCoeff * equirecty + aziequiCoeff * aziequiy + mollweideCoeff * mollweidey
	local z = sphereCoeff * spherez + cylCoeff * cylz + equirectCoeff * equirectz + aziequiCoeff * aziequiz + mollweideCoeff * mollweidez
	gl.glVertex3d(x,y,z)
end

function App:update()
	gl.glClearColor(0, 0, 0, 1)
	gl.glClear(bit.bor(gl.GL_COLOR_BUFFER_BIT, gl.GL_DEPTH_BUFFER_BIT))
	self.shader:use()
	--self.tex:enable()
	self.tex:bind(0)
	self.continentTex:bind(1)
	gl.glColor3f(1,1,1)
	for j=0,jdivs-1 do
		gl.glColor3f(1,1,1)
		gl.glBegin(gl.GL_TRIANGLE_STRIP)
		for i=0,idivs do
			local aziFrac = i/idivs
			vertex(aziFrac, (j+1)/jdivs, 0)
			vertex(aziFrac, j/jdivs, 0)
		end
		gl.glEnd()
	end
	self.continentTex:unbind(1)
	self.tex:unbind(0)
	--self.tex:disable()
	self.shader:useNone()
	
-- [[
	gl.glPointSize(3)
	gl.glBegin(gl.GL_POINTS)
	gl.glColor3f(1,0,0)
	gl.glVertex3d(com:unpack())
	gl.glEnd()
	gl.glPointSize(1)

	for mask,com in pairs(comForMask) do
		gl.glLineWidth(3)
		gl.glDepthMask(gl.GL_FALSE)
		gl.glColor3f(0,0,0)
		gl.glBegin(gl.GL_LINES)
		gl.glVertex3d(0,0,0)
		
		gl.glVertex3d((com * 1.5):unpack())
		
		gl.glEnd()
		gl.glDepthMask(gl.GL_TRUE)

		gl.glLineWidth(1)
		gl.glBegin(gl.GL_LINES)
		gl.glColor3f(
			bit.band(mask, 0xff)/0xff, 
			bit.band(bit.rshift(mask, 8), 0xff)/0xff, 
			bit.band(bit.rshift(mask, 16), 0xff)/0xff) 
		gl.glVertex3d(0,0,0)
		gl.glVertex3d((com * 1.5):unpack())
		gl.glEnd()
	end
--]]

	App.super.update(self)
end


local weightFields = {
	'sphereCoeff',
	'cylCoeff',
	'equirectCoeff',
	'aziequiCoeff',
	'mollweideCoeff',
}

function App:updateGUI()
	ig.luatableInputInt('idivs', _G, 'idivs')
	ig.luatableInputInt('jdivs', _G, 'jdivs')
	ig.luatableCheckbox('normalize weights', _G, 'normalizeWeights')
	local changed
	for _,field in ipairs(weightFields) do
		if ig.luatableSliderFloat(field, _G, field, 0, 1) then
			changed = field
		end
	end
	if normalizeWeights and changed then
		local restFrac = 1 - _G[changed]
		local totalRest = 0
		for _,field in ipairs(weightFields) do
			if field ~= changed then
				totalRest = totalRest + _G[field]
			end
		end
		for _,field in ipairs(weightFields) do
			if field ~= changed then
				if totalRest == 0 then
					_G[field] = 0
				else
					_G[field] = restFrac * _G[field] / totalRest
				end
			end
		end
	end
end

App():run()
