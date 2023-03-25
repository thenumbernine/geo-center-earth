#!/usr/bin/env luajit
require 'ext'
local matrix = require 'matrix'
local vec3d = require 'vec-ffi.vec3d'

local charts = require 'geographic-charts'
local wgs84 = charts.WGS84

-- disable this to calculate the COM of the entire plate, not just above-water
-- ofc the COM of the whole earth will be the center of the earth, so that wont provide any useful information.
local continentsOnly = not cmdline.allmass

-- [[
local Image = require 'image'
-- (this is too big)
--local bathImg = Image'visibleearth/gebco_08_rev_bath_21600x10800.png'
-- use our current data
local bathImg = Image'gebco_08_rev_bath_3600x1800_color.jpg'
-- use the pleistoscene bathymetric data (pre-Younger-Dryas-flood)
--local bathImg = Image'Global_sea_levels_during_the_last_Ice_Age_4320x2160-bath.png'
assert(bathImg)
--assert(bathImg.channels == 1)
print('width', bathImg.width, 'height', bathImg.height)
--]]

-- [[ build continentImg from me winging it
local continentImg = Image'continent-mask-3.png'
print('continent width', continentImg.width, 'height', continentImg.height, 'channels', continentImg.channels)
assert(continentImg.channels >= 3)
--assert(continentImg.width == bathImg.width)
--assert(continentImg.height == bathImg.height)
--continentImg = continentImg:resize(bathImg.width, bathImg.height)
bathImg = bathImg:resize(continentImg.width, continentImg.height)
--]]
--[[ build continentImg from tectonicplates plates data
-- the polygons are too complicated for gl so i have to software render them
local json = require 'dkjson'
local polys = table()
local layers = {
	{name='plates', data=assert(json.decode(file'tectonicplates/GeoJSON/PB2002_plates.json':read()))},
}
for _,layer in ipairs(layers) do
	for _,feature in ipairs(layer.data.features) do
		if feature.geometry.type == 'LineString' then
		elseif feature.geometry.type == 'Polygon' then
			for _,poly in ipairs(feature.geometry.coordinates) do
				polys:insert(poly)
			end
		elseif feature.geometry.type == 'MultiPolygon' then
			for _,group in ipairs(feature.geometry.coordinates) do
				for _,poly in ipairs(group) do
					polys:insert(poly)
				end		
			end		
		else
			error('here')
		end
	end
end
for _,poly in ipairs(polys) do
	poly.color = matrix{math.random(), math.random(), math.random()}
	poly.color = poly.color / poly.color:norm()
end
--local cw, ch = 2048, 1024
local cw, ch = 200, 100
local continentImg = Image(cw, ch, 3, 'unsigned char', function(i,j)
print(i,j)
	local x = i/cw*360-180
	local y = j/ch*180-90
	local totaltheta = 0
	for _,p in ipairs(polys) do
		local n = #p
		local theta = 0
		for i=1,n do
			local coord = p[i]
			local i2 = (i%n)+1
			local x1 = coord[1]
			local y1 = coord[2]
			local coord2 = p[i2]
			local x2 = coord2[1]
			local y2 = coord2[2]
			local dx1 = x1 - x
			local dy1 = y1 - y
			local dx2 = x2 - x
			local dy2 = y2 - y
			local sindtheta = (dx1 * dy2 - dx2 * dy1) / math.sqrt(
				(dx1 * dx1 + dy1 * dy1)
				* (dx2 * dx2 + dy2 * dy2)
			)
			local dtheta = math.asin(math.clamp(sindtheta,-1,1))
			theta = theta + dtheta
		end
		-- if θ is approx 0 then we're outside the poly
		-- if it's some integer of 2 pi then we're inside the poly
		totaltheta = totaltheta + theta
	end
	return totaltheta / (2 * math.pi) / 3 + 1.5, 0, 0
end)
--]]

local comForMask = {}
local comLatLonHeightForMask = {}
local areaForMask = {}

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
local numpixels = bathImg.width * bathImg.height

local err_lon = 0
local err_lat = 0
local err_height = 0
local ravg = 0

local landArea = 0
local totalArea = 0
local e = 0
local hist = range(0,255):map(function(i) return 0, i end)
local step = 8
local max_err_lat = 0
for j=0,bathImg.height-1,step do
	local lat = (.5 - (j+.5)/bathImg.height) * 180
	local dtheta = (math.pi * step) / bathImg.height
	local dphi = (2 * math.pi * step) / bathImg.width
	
	--[[ spherical area element (using physicist spherical coordinates)
	U^μ = [r sinθ cosφ, r sinθ sinφ, r cosθ]
	∂U^μ/∂r = [sinθ cosφ, sinθ sinφ, cosθ]				|∂U^μ/∂r| = 1
	∂U^μ/∂θ = [r cosθ cosφ, r cosθ sinφ, -r sinθ]		|∂U^μ/∂θ| = r
	∂U^μ/∂φ = [-r sinθ sinφ, r sinθ cosφ, 0]			|∂U^μ/∂φ| = r sinθ
	s.t. det|∂U^μ/dX^ν| = Π_ν |∂U^μ/dX^ν| = r^2 sinθ
	--]]
	--[[
	local theta = (j+.5) / bathImg.height * math.pi
	local sintheta = math.sin(theta)
	local dU_dtheta = 1
	local dU_dphi = sintheta
	local dA = dU_dtheta * dU_dphi * dtheta * dphi
	--]]
	-- [[ same but for the WGS84 model
	local dA = math.abs(wgs84:dx_dsphere_det_h_eq_0(lat)) * dtheta * dphi 
	--]]

	--assert(math.isfinite(dA))
	for i=0,bathImg.width-1,step do
		e = i + bathImg.width * j
		local lon = ((i+.5)/bathImg.width - .5) * 360
		local bathr = bathImg and bathImg.buffer[0 + 3 * e] 
		local bathg = bathImg and bathImg.buffer[1 + 3 * e] 
		local bathb = bathImg and bathImg.buffer[2 + 3 * e] 
	
		--if bathImg == nil or bathr >= 255 then
		if not continentsOnly
		or bathImg == nil 
		or (bathr == 0 and bathg == 0 and bathb == 0) 
		then
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
		print((100*e/numpixels)..'% complete')
		--print('com', com)
		--print('landArea', landArea)
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
local comLen = com:norm()
print('com norm', comLen)
local comUnit = com / comLen 
print('com = ', com)
print('comUnit = ', comUnit)
local comLatLon = matrix{wgs84:chartInv((comUnit * wgs84.a):unpack())}
print('com lat lon =', comLatLon) 
--]=]

local masks = table.keys(comForMask):sort()
for _,mask in ipairs(masks) do
	comForMask[mask] = comForMask[mask] / areaForMask[mask]
	comLatLonHeightForMask[mask] = matrix{wgs84:chartInv((comForMask[mask] * wgs84.a):unpack())}
	print('mask', ('%x'):format(mask), 'com', comForMask[mask], 'com lat lon', comLatLonHeightForMask[mask])
end
--[[
comparing this to the guy who said Giza was at the center of mass of all land on earth:
full earth 		com lat lon =	[43.742450656403, 28.632616395901]		<- next to Black Sea.  Alleged (by ... cite) COM of all land area is supposed to be at Giza, Egypt

comparing these to the Alan Moen crescents next to blonde tribes which he points out are close to the center of mass of each continent. 
mask	7f8dac	com lat lon	[56.007823753727, -103.07996581373]			<- North America, in Manitoba? ... vs. crescent is Turtle Mountain Park at 49.049164,-100.0632356
mask	b082ad	com lat lon	[-13.754153820306, -60.126821755646]		<- South America ... vs. crescent nearby is Parque Estadual do Guira?
mask	72a17f	com lat lon	[47.162438928774, 78.535697981186]			<- Eurasia, in Kazakhstan ... vs. Urumqi China / Bogeda Peak at 43.8016657,88.3237452
mask	7a9afb	com lat lon	[6.3722142780304, 18.526880794863]			<- Africa, C.A.R ... vs Bongo Massif at 7.6029787,21.2410182
mask	82b4fc	com lat lon	[-24.991315573585, 134.96457257506]			<- Australia, near Alice Springs ... vs Mount Olga, Australia at -25.3002455,130.7330146
mask	aae6fe	com lat lon	[-6.201910350677, 147.3285295677]			<- Pacific Plate, on P.N.G. 
mask	be9d8a	com lat lon	[-85.850024779859, 80.117014944601]			<- Antarctica
--]]

local angleDifferences = matrix{#masks, #masks}:lambda(function(i,j)
	local dot = comForMask[masks[i]]:unit() *
				comForMask[masks[j]]:unit()
	return math.deg(math.acos(math.clamp(dot, -1, 1)))
end)
print'masks:'
print(matrix(masks))
print('angle differences:')
print(angleDifferences) 

print'resizing images...'
local bathImgDownsized = bathImg:resize(2048,1024):rgb()
local continentImgDownsized = continentImg:resize(2048,1024):rgb():setChannels(4)
for i=3,continentImgDownsized.width*continentImgDownsized.height*4,4 do
	continentImgDownsized.buffer[i] = 127
end
print('resized bathImg size', bathImgDownsized.width, bathImgDownsized.height)
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

	self.bathTex = GLTex2D{
		image = bathImgDownsized,
		minFilter = gl.GL_LINEAR,
		magFilter = gl.GL_LINEAR,
		generateMipmap = true,
	}
	self.colorTex = GLTex2D{
		filename = 'earth-color.png',
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
uniform sampler2D bathTex;
uniform sampler2D colorTex;
uniform sampler2D continentTex;
uniform float gamma;
uniform float alpha1;
uniform float alpha2;
varying vec3 color;
varying vec2 tc;
void main() {
	//gl_FragColor = pow(texture2D(bathTex, tc), vec4(gamma));
	gl_FragColor = step(vec4(gamma), texture2D(bathTex, tc));
	
	gl_FragColor = mix(gl_FragColor, texture2D(continentTex, tc), alpha1);
	gl_FragColor = mix(gl_FragColor, texture2D(colorTex, tc), alpha2);
}
]],
		uniforms = {
			bathTex = 0,
			continentTex = 1,
			colorTex = 2,
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
alpha1 = .5
alpha2 = .5
gamma = 1

-- bleh conventions:
--  physicist spherical: azimuthal = θ, longitude = φ
--  mathematician spherical: azimuthal = φ, longitude = θ
--  geographer: latitude = φ, longitude = λ
-- rather than pick one im just gonna say 'azimuthal, latitude, longitude'
-- oh and unitLonFrac is gonna be from 0=america to 1=east asia, so unitLonFrac==.5 means lon==0
local function vertexpos(lat, lon, height)
	local latrad = math.rad(lat)
	local azimuthal = .5*math.pi - latrad
	local aziFrac = azimuthal / math.pi

	local lonrad = math.rad(lon)
	local lonFrac = lonrad / (2 * math.pi)
	local unitLonFrac = lonFrac + .5
	
	gl.glTexCoord2d(unitLonFrac, aziFrac)

	local spheroidx, spheroidy, spheroidz = wgs84:chart(lat, lon, height)
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

	local equirectx, equirecty, equirectz = charts.Equirectangular:chart(lat, lon, height)
	local aziequix, aziequiy, aziequiz = charts['Azimuthal equidistant']:chart(lat, lon, height)
	local mollweidex, mollweidey, mollweidez = charts.Mollweide:chart(lat, lon, height)

	local x = spheroidCoeff * spheroidx + cylCoeff * cylx + equirectCoeff * equirectx + aziequiCoeff * aziequix + mollweideCoeff * mollweidex
	local y = spheroidCoeff * spheroidy + cylCoeff * cyly + equirectCoeff * equirecty + aziequiCoeff * aziequiy + mollweideCoeff * mollweidey
	local z = spheroidCoeff * spheroidz + cylCoeff * cylz + equirectCoeff * equirectz + aziequiCoeff * aziequiz + mollweideCoeff * mollweidez
	return x / wgs84.a, y / wgs84.a, z / wgs84.a
end

local function vertex(lat, lon, height)
	gl.glVertex3d(vertexpos(lat, lon, height))
end

local function getbasis(lat, lon, height)
	local spheroidu, spheroidv, spheroidw = wgs84:basis(lat, lon, height)
	local cylu, cylv, cylw = charts.cylinder:basis(lat, lon, height)
	for _,basis in ipairs{
		spheroidu, spheroidv, spheroidw,
		cylu, cylv, cylw
	} do
		-- rotate back so y is up
		basis.y, basis.z = basis.z, -basis.y
		-- now rotate so prime meridian is along -z instead of +x
		basis.x, basis.z = -basis.z, basis.x
	end

	local equirectu, equirectv, equirectw = charts.Equirectangular:basis(lat, lon, height)
	local aziequiu, aziequiv, aziequiw = charts['Azimuthal equidistant']:basis(lat, lon, height)
	local mollweideu, mollweidev, mollweidew = charts.Mollweide:basis(lat, lon, height)

	local u = spheroidu * spheroidCoeff + cylu * cylCoeff + equirectu * equirectCoeff + aziequiu * aziequiCoeff + mollweideu * mollweideCoeff
	local v = spheroidv * spheroidCoeff + cylv * cylCoeff + equirectv * equirectCoeff + aziequiv * aziequiCoeff + mollweidev * mollweideCoeff
	local w = spheroidw * spheroidCoeff + cylw * cylCoeff + equirectw * equirectCoeff + aziequiw * aziequiCoeff + mollweidew * mollweideCoeff
	return u,v,w
end

function App:update()
	gl.glClearColor(0, 0, 0, 1)
	gl.glClear(bit.bor(gl.GL_COLOR_BUFFER_BIT, gl.GL_DEPTH_BUFFER_BIT))
	self.shader:use()
	gl.glUniform1f(self.shader.uniforms.alpha1.loc, alpha1)
	gl.glUniform1f(self.shader.uniforms.alpha2.loc, alpha2)
	gl.glUniform1f(self.shader.uniforms.gamma.loc, gamma)
	--self.bathTex:enable()
	self.bathTex:bind(0)
	self.continentTex:bind(1)
	self.colorTex:bind(2)
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
	self.colorTex:unbind(2)
	self.continentTex:unbind(1)
	self.bathTex:unbind(0)
	--self.bathTex:disable()
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

		local function drawMarker(com, rgb)
			local lat, lon, height = com[1], com[2], 0
			local r = bit.band(rgb, 0xff)/0xff
			local g = bit.band(bit.rshift(rgb, 8), 0xff)/0xff
			local b = bit.band(bit.rshift(rgb, 16), 0xff)/0xff
			
			gl.glLineWidth(3)
			gl.glDepthMask(gl.GL_FALSE)
			gl.glColor3f(0,0,0)
			gl.glBegin(gl.GL_LINE_STRIP)
			drawCOMLine(com)
			gl.glEnd()
			gl.glDepthMask(gl.GL_TRUE)

			gl.glLineWidth(1)
			gl.glBegin(gl.GL_LINE_STRIP)
			gl.glColor3f(r,g,b)
			drawCOMLine(com)
			gl.glEnd()
		
			local pt = vec3d(vertexpos(lat, lon, height))
			local du, dv, dw = getbasis(lat, lon, height)
			
			for j=0,1 do	-- radius
				local rad
				if j == 0 then
					rad = .015
					gl.glColor3f(0,0,0)
					gl.glDepthMask(gl.GL_FALSE)
				else
					rad = .01
					gl.glColor3f(r,g,b)
				end
				gl.glBegin(gl.GL_POLYGON)
				local polydivs = 20
				for i=1,polydivs do
					local th = i/polydivs*2*math.pi
					local c = rad * math.cos(th)
					local s = rad * math.sin(th)
					gl.glVertex3d((pt + du * c + dv * s - dw * .001):unpack())
				end
				gl.glEnd()
				gl.glDepthMask(gl.GL_TRUE)
			end
		end

		drawMarker(comLatLon, 0xff)
		for mask,com in pairs(comLatLonHeightForMask) do
			drawMarker(com, mask)
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
	ig.luatableInputFloat('alpha1', _G, 'alpha1')
	ig.luatableInputFloat('alpha2', _G, 'alpha2')
	ig.luatableInputFloat('gamma', _G, 'gamma')
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
