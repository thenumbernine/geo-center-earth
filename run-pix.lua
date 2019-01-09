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

local function convertSpheroid3DToLatLon(x,y,z)
	-- this much is always true
	local phi = math.atan2(y, x);

--[[ radial distance for spheroid:
calculating r,theta based on r2, z

r2(r,theta) = sqrt(x^2 + y^2) = (N+h) cosTheta
z(r,theta) = (N * (1 - eccentricitySquared) + height) * sinTheta

r(r2,z) = (N+h)^2 + ( N eps^2 - 2 (N+h) ) N eps^2 sin(theta)^2
theta(r2,z) = atan2(...) 
r[0] = (x^2 + y^2 + z^2)^.5
theta[0] = atan2(z, (x^2 + y^2)^.5)
--]]

	-- spherical:
	local r2 = math.sqrt(x*x + y*y);
	local r = math.sqrt(r2*r2 + z*z);
	local theta = math.atan2(z, r2);

	-- lon, lat:
	return (math.deg(phi) + 180) % 360 - 180, 
			(math.deg(theta) + 90) % 180 - 90
end


--- END CUT FROM run.lua

--[[
local Image = require 'image'
local img = Image'visibleearth/gebco_08_rev_bath_21600x10800.png'
assert(img)
local w, h, ch = img:size()
assert(ch == 1)
--]]
-- [[
local w, h = 2000, 1000
--]]

local matrix = require 'matrix'
local com = matrix{0,0,0}
local mass = 0

local lastTime = os.time()
local imgsize = w * h

local err_lon = 0
local err_lat = 0

local landArea = 0
local totalArea = 0
local e = 0
local hist = range(0,255):map(function(i) return 0, i end)
for j=0,h-1 do
	local lat = (.5 - (j+.5)/h) * 180
	local dA = math.abs(dx_dsphere_det_h_eq_0(lat)) * (2 * math.pi) / w * math.pi / h
	for i=0,w-1 do
		local lon = ((i+.5)/w - .5) * 360
		local v = img and img.buffer[e] e=e+1
		if img == nil or v == 255 then
			-- consider this coordinate for land sum
			
			local pt = matrix{convertLatLonToSpheroid3D(lon, lat)}
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
com = com / comNorm 
print('com = ', com)
local latLon = matrix{convertSpheroid3DToLatLon(com:unpack())}
print('com lon lat =', latLon) 

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
