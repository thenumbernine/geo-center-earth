#!/usr/bin/env luajit
require 'ext'

local charts = require 'geographic-charts'
local wgs84 = charts.WGS84

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
local comLatLonHeightForMask = {}
local areaForMask = {}

local matrix = require 'matrix'
local com = matrix{0,0,0}
local mass = 0

--[[
local com = matrix{0.6047097872861, 0.35902954396197, 0.7109316842868}
print('com',com)
print('lat lon height of com',wgs84:chartInv(com:unpack()))
--os.exit()
--]]


-- [=[
local lastTime = os.time()
local imgsize = w * h

local err_lon = 0
local err_lat = 0
local err_height = 0
local ravg = 0

local landArea = 0
local totalArea = 0
local e = 0
local hist = range(0,255):map(function(i) return 0, i end)
local step = 600
local max_err_lat  = 0
for j=0,h-1,step do
	local lat = (.5 - (j+.5)/h) * 180
	--local dA = math.abs(wgs84:dx_dsphere_det_h_eq_0(lat)) * (2 * math.pi) / w * math.pi / h
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

			local height = 0
			local pt = matrix{wgs84:chart(lat, lon, height)} / wgs84.a
			--assert(math.isfinite(pt[1]))
			--assert(math.isfinite(pt[2]))
			--assert(math.isfinite(pt[3]))
			-- [[ verify accuracy
			local lat2, lon2, height2 = wgs84:chartInv((pt * wgs84.a):unpack())
--if i == 0 then print('lat ' .. lat .. ' lat2 ' .. lat2) end
			err_lon = err_lon + math.abs(lon-lon2) 
			local this_err_lat = math.abs(lat-lat2)
			max_err_lat = math.max(max_err_lat, this_err_lat)
			err_lat = err_lat + this_err_lat
			err_height = err_height + math.abs(height2-height)
-- max err can get significant and that leads to a significant total error
--print(math.abs(lat-lat2))
			--]]

			ravg = ravg + (pt * pt) * dA

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
print('reconstruction lon error', err_lon)
print('reconstruction lat error', err_lat)
print('reconstruction height error', err_height)
print('max lat error', max_err_lat) 
print('landArea', landArea)
print('totalArea', totalArea)
print('totalArea / 4pi', totalArea / (4 * math.pi))
print('ravg', ravg / landArea)
print('% of earth covered by land =', (landArea / totalArea) * 100)
print('% of earth covered by water =', (1 - landArea / totalArea) * 100)
local comNorm = com:norm()
print('com norm', comNorm)
local com2 = com / comNorm 
print('com = ', com)
print('com2 = ', com2)
local latLon = matrix{wgs84:chartInv((com2 * wgs84.a):unpack())}
print('com lat lon =', latLon) 
--]=]

for _,mask in ipairs(table.keys(comForMask)) do
	comForMask[mask] = comForMask[mask] / areaForMask[mask]
	print('mask', ('%x'):format(mask), 'com', comForMask[mask])
	comLatLonHeightForMask[mask] = matrix{wgs84:chartInv((comForMask[mask] * wgs84.a):unpack())}
end

print'resizing images...'
local imgDownsized = img:resize(2048,1024):rgb()
local continentImgDownsized = continentImg:resize(2048,1024):rgb():setChannels(4)
for i=3,continentImgDownsized.width*continentImgDownsized.height*4,4 do
	continentImgDownsized.buffer[i] = 127
end
print('resized img size', imgDownsized.width, imgDownsized.height)
print'done'


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

	self.tex = GLTex2D{
		image = imgDownsized,
		minFilter = gl.GL_LINEAR,
		magFilter = gl.GL_LINEAR,
		generateMipmap = true,
	}
	self.continentTex = GLTex2D{
		image = continentImgDownsized,
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
drawCOMs = true
normalizeWeights = true
spheroidCoeff = 0
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
local function vertex(lat, lon, height)
	local latrad = math.rad(lat)
	local azimuthal = .5*math.pi - latrad
	local aziFrac = azimuthal / math.pi

	local lonrad = math.rad(lon)
	local lonFrac = lonrad / (2 * math.pi)
	local unitLonFrac = lonFrac + .5
	
	gl.glTexCoord2d(unitLonFrac, aziFrac)

	local spheroidx, spheroidy, spheroidz = wgs84:chart(lat, lon, height)
	spheroidx = spheroidx / wgs84.a
	spheroidy = spheroidy / wgs84.a
	spheroidz = spheroidz / wgs84.a
	-- rotate back so y is up
	spheroidy, spheroidz = spheroidz, -spheroidy
	-- now rotate so prime meridian is along -z instead of +x
	spheroidx, spheroidz = -spheroidz, spheroidx

	-- cylindrical
	local cylx, cyly, cylz = charts.cylinder:chart(lat, lon, height)
	-- rotate back so y is up
	cyly, cylz = cylz, -cyly
	-- now rotate so prime meridian is along -z instead of +x
	cylx, cylz = -cylz, cylx

	local equirectx, equirecty, equirectz = charts.equirectangular:chart(lat, lon, height)
	local aziequix, aziequiy, aziequiz = charts.azimuthalEquidistant:chart(lat, lon, height)
	local mollweidex, mollweidey, mollweidez = charts.mollweide:chart(lat, lon, height)

	local x = spheroidCoeff * spheroidx + cylCoeff * cylx + equirectCoeff * equirectx + aziequiCoeff * aziequix + mollweideCoeff * mollweidex
	local y = spheroidCoeff * spheroidy + cylCoeff * cyly + equirectCoeff * equirecty + aziequiCoeff * aziequiy + mollweideCoeff * mollweidey
	local z = spheroidCoeff * spheroidz + cylCoeff * cylz + equirectCoeff * equirectz + aziequiCoeff * aziequiz + mollweideCoeff * mollweidez
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
			local azimuthal = aziFrac * math.pi-- azimuthal angle
			local latrad = .5*math.pi - azimuthal	-- latitude
			local lat = math.deg(latrad)

			local unitLonFrac = (j+1)/jdivs
			local lonFrac = unitLonFrac - .5
			local lonrad = lonFrac * 2 * math.pi			-- longitude
			local lon = math.deg(lonrad)
			vertex(lat, lon, 0)

			local unitLonFrac = j/jdivs
			local lonFrac = unitLonFrac - .5
			local lonrad = lonFrac * 2 * math.pi			-- longitude
			local lon = math.deg(lonrad)
			vertex(lat, lon, 0)
		end
		gl.glEnd()
	end
	self.continentTex:unbind(1)
	self.tex:unbind(0)
	--self.tex:disable()
	self.shader:useNone()

	if drawCOMs then
		local function drawCOMLine(com)
			local lat, lon, height = table.unpack(com)
			local n = 10
			for i=0,n do
				local height = 2*i/n
				vertex(lat, lon, height)
			end
		end

		local function drawCOMOutlinedLine(com, mask)
			gl.glLineWidth(3)
			gl.glDepthMask(gl.GL_FALSE)
			gl.glColor3f(0,0,0)
			gl.glBegin(gl.GL_LINES)
			drawCOMLine(com)
			gl.glEnd()
			gl.glDepthMask(gl.GL_TRUE)

			gl.glLineWidth(1)
			gl.glBegin(gl.GL_LINES)
			gl.glColor3f(
				bit.band(mask, 0xff)/0xff, 
				bit.band(bit.rshift(mask, 8), 0xff)/0xff, 
				bit.band(bit.rshift(mask, 16), 0xff)/0xff) 
			drawCOMLine(com)
			gl.glEnd()
		end

		gl.glPointSize(3)
		gl.glBegin(gl.GL_POINTS)
		gl.glColor3f(1,0,0)
		gl.glVertex3d(com:unpack())
		gl.glEnd()
		gl.glPointSize(1)

		for mask,com in pairs(comLatLonHeightForMask) do
			drawCOMOutlinedLine(com, mask)
		end
	end

	App.super.update(self)
end


local weightFields = {
	'spheroidCoeff',
	'cylCoeff',
	'equirectCoeff',
	'aziequiCoeff',
	'mollweideCoeff',
}

function App:updateGUI()
	ig.luatableInputInt('idivs', _G, 'idivs')
	ig.luatableInputInt('jdivs', _G, 'jdivs')
	ig.luatableCheckbox('draw coms', _G, 'drawCOMs')
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
