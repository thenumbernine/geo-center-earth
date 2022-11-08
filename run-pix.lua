#!/usr/bin/env luajit
require 'ext'

--- BEGIN CUT FROM run.lua

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

-- https://gis.stackexchange.com/questions/28446/computational-most-efficient-way-to-convert-cartesian-to-geodetic-coordinates
local function convertSpheroid3DToLatLon(x,y,z)
	--[[
	-- this much is always true
	local phi = math.atan2(y, x);
	local theta
	for i=1,10000 do
		-- spherical:
		local r2 = math.sqrt(x*x + y*y);
		local newtheta = math.atan2(z, r2);
		if theta then
			local dtheta = math.abs(newtheta - theta)
			--print(dtheta, z)
			if dtheta < 1e-15 then break end
		end
		theta = newtheta
		x,y,z = convertLatLonToSpheroid3D( math.deg(phi), math.deg(theta) )
	end
	--]]
	-- [[ sphere approx
	local phi = math.atan2(y, x)
	local theta = math.atan2(z, math.sqrt(x*x + y*y))
	--]]

	-- lon, lat:
	return (math.deg(phi) + 180) % 360 - 180, 
			(math.deg(theta) + 90) % 180 - 90
end


--- END CUT FROM run.lua

-- [[
local Image = require 'image'
local img = Image'visibleearth/gebco_08_rev_bath_21600x10800.png'
assert(img)
local w, h, ch = img:size()
assert(ch == 1)
--]]
--[[
local w, h = 200, 100
--]]

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
local step = 5
for j=0,h-1,step do
	local lat = (.5 - (j+.5)/h) * 180
	local dA = math.abs(dx_dsphere_det_h_eq_0(lat)) * (2 * math.pi) / w * math.pi / h
	--assert(math.isfinite(dA))
	for i=0,w-1,step do
		local lon = ((i+.5)/w - .5) * 360
		local v = img and img.buffer[e] e=e+1
		if img == nil or v == 255 then
			-- consider this coordinate for land sum
			
			local pt = matrix{convertLatLonToSpheroid3D(lon, lat)}
			--assert(math.isfinite(pt[1]))
			--assert(math.isfinite(pt[2]))
			--assert(math.isfinite(pt[3]))
			-- [[ verify accuracy
			local lon2, lat2 = convertSpheroid3DToLatLon(pt:unpack())
			err_lon = err_lon + math.abs(lon-lon2) 
			err_lat = err_lat + math.abs(lat-lat2)
			--]]
			com = com + pt * dA
			landArea = landArea + dA
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
print('reconstruction lat err', err_lat)
print('reconstruction lon err', err_lon)
print('landArea', landArea)
print('totalArea', totalArea)
print('totalArea / 4pi', totalArea / (4 * math.pi))
print('% of earth covered by water =', landArea / totalArea)
local comNorm = com:norm()
print('com norm', comNorm)
local com2 = com / comNorm 
print('com = ', com)
print('com2 = ', com2)
local latLon = matrix{convertSpheroid3DToLatLon(com2:unpack())}
print('com lon lat =', latLon) 
--]=]

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
end

-- globals for gui access
idivs = 100
jdivs = 100
sphereCoeff = 0
polarCoeff = 1
rectCoeff = 0

local function vertex(i,j)
	local u = i/idivs
	local v = j/jdivs
	local theta = u*math.pi
	local phi = v*math.pi*2
	local costh, sinth = math.cos(theta), math.sin(theta)
	local cosphi, sinphi = math.cos(phi), math.sin(phi)
	gl.glTexCoord2d(v, u)
	
	local spherex = sinth * cosphi
	local spherey = sinth * sinphi
	local spherez = costh

	local rectx = 2 * v - 1
	local recty = (1 - 2 * u) * .5
	local rectz = 0

	local polarx = u * cosphi
	local polary = u * sinphi
	local polarz = 0

	local x = sphereCoeff * spherex + rectCoeff * rectx + polarCoeff * polarx
	local y = sphereCoeff * spherey + rectCoeff * recty + polarCoeff * polary
	local z = sphereCoeff * spherez + rectCoeff * rectz + polarCoeff * polarz
	
	gl.glVertex3d(x,y,z)
end

function App:update()
	gl.glClearColor(0, 0, 0, 1)
	gl.glClear(bit.bor(gl.GL_COLOR_BUFFER_BIT, gl.GL_DEPTH_BUFFER_BIT))
	self.tex:enable()
	self.tex:bind()
	gl.glColor3f(1,1,1)
	for i=0,idivs-1 do
		gl.glColor3f(1,1,1)
		gl.glBegin(gl.GL_TRIANGLE_STRIP)
		for j=0,jdivs do
			vertex(i+1,j)
			vertex(i,j)
		end
		gl.glEnd()
	end
	self.tex:unbind()
	self.tex:disable()
	
	gl.glColor3f(1,0,0)
	gl.glPointSize(3)
	gl.glBegin(gl.GL_POINTS)
	gl.glVertex3d(com:unpack())
	gl.glEnd()
	gl.glPointSize(1)

	App.super.update(self)
end


function App:updateGUI()
	ig.luatableInputInt('idivs', _G, 'idivs')
	ig.luatableInputInt('jdivs', _G, 'jdivs')
	ig.luatableSliderFloat('sphereCoeff', _G, 'sphereCoeff', 0, 1)
	ig.luatableSliderFloat('polarCoeff', _G, 'polarCoeff', 0, 1)
	ig.luatableSliderFloat('rectCoeff', _G, 'rectCoeff', 0, 1)
end

App():run()
