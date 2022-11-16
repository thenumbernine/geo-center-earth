--[[
I use these often enough that they are going to go into a library soon enough

2D charts will be xy coordinates, z will be for height

3D charts  are z+ = north pole, x+ = prime meridian


GAAAHHH STANDARDS
physics spherical coordinates: the longitude is φ and the latitude (starting at the north pole and going down) is θ ...
mathematician spherical coordinates: the longitude is θ and the latitude is φ ...
geographic / map charts: the longitude is λ and the latitude is φ ...
so TODO change the calc_* stuff from r_θφ to h_φλ? idk ...

--]]
		
-- using geographic labels: lat = φ, lon = λ
local symmath = require 'symmath'
-- input 
local latvar = symmath.var'lat'
local lonvar = symmath.var'lon'
local heightvar = symmath.var'height'
-- expressions
local latradval = latvar * symmath.pi / 180
local lonradval = lonvar * symmath.pi / 180
	
local charts = {
	(function()
		local c = {}
		
		c.name = 'WGS84'
		
		-- specific to WGS84:
		c.inverseFlattening = 298.257223563
		c.eccentricitySquared = (2 * c.inverseFlattening - 1) / (c.inverseFlattening * c.inverseFlattening)
		
		c.a = 6378137	-- m ... earth equitorial radius
		c.b = 6356752.3142	-- m ... earth polar radius
		
		function c:calc_N(sinTheta, equatorialRadius, eccentricitySquared)
			local denom = math.sqrt(1 - eccentricitySquared * sinTheta * sinTheta)
			return equatorialRadius / denom
		end
		
		function c:calc_dN_dTheta(sinTheta, cosTheta, equatorialRadius, eccentricitySquared)
			local denom = math.sqrt(1 - eccentricitySquared * sinTheta * sinTheta)
			return eccentricitySquared * sinTheta * cosTheta * equatorialRadius / (denom * denom * denom)
		end

		-- |d(x,y,z)/d(h,θ,φ)| for h=0
		function c:dx_dsphere_det_h_eq_0(lat) 
			local theta = math.rad(lat)		-- spherical inclination angle (not azumuthal θ)
			local sinTheta = math.sin(theta)
			local cosTheta = math.cos(theta)
			
			local h = 0
			local N = self:calc_N(sinTheta, self.a, self.eccentricitySquared)
			local dN_dTheta = calc_dN_dTheta(sinTheta, cosTheta, self.a, eccentricitySquared)
			local cosTheta2 = cosTheta * cosTheta
			return -N * (
				N * cosTheta 
				+ self.eccentricitySquared * cosTheta2 * N * cosTheta
				+ self.eccentricitySquared * cosTheta2 * dN_dTheta * sinTheta
			)
		end

		-- returns x,y,z in meters
		-- lat = [-90,90] in degrees
		-- lon = [-180,180] in degrees
		-- height >= 0 in meters
		-- returns: x,y,z in meters
		function c:chart(lat, lon, height)
			local phi = math.rad(lon)		-- spherical φ
			local theta = math.rad(lat)		-- spherical inclination angle (not azumuthal θ)
			local cosTheta = math.cos(theta)
			local sinTheta = math.sin(theta)
			
			local N = self:calc_N(sinTheta, self.a, self.eccentricitySquared)
			
			local NPlusH = N + height
			return 
				NPlusH * cosTheta * math.cos(phi),
				NPlusH * cosTheta * math.sin(phi),
				(N * (1 - self.eccentricitySquared) + height) * sinTheta
		end
			
		-- x,y,z = meters
		-- returns lat (degrees), lon (degrees), height (meters)
		-- lat and lon has the same range as chart()
		--
		-- https://gis.stackexchange.com/questions/28446/computational-most-efficient-way-to-convert-cartesian-to-geodetic-coordinates
		function c:chartInv(x, y, z)
			-- this much is always true
			local phi = math.atan2(y, x);
			local theta			-- spherical inclination angle
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
				x,y,z = self:chart(math.deg(theta), math.deg(phi), 0)
			end
			
			local NPlusHTimesCosTheta = math.sqrt(x*x + y*y)
			local NPlusH = NPlusHTimesCosTheta / math.cos(theta)
			local height = NPlusH - self:calc_N(math.sin(theta), self.a, self.eccentricitySquared)

			-- lat, lon, height:
			return 
				math.deg(theta),
				(math.deg(phi) + 180) % 360 - 180, 
				height
		end
	
		return c
	end)(),
	
	(function()
		local rval = heightvar + 1
		-- results
		local xval = rval * symmath.cos(lonradval)
		local yval = rval * symmath.sin(lonradval)
		local zval = rval * latradval

		local f = symmath.export.Lua:toFunc{
			input = {
				-- args
				latvar, lonvar, heightvar,
				-- gui vars
			},
			output = {xval, yval, zval},
		}

		local c = {}
		c.name = 'cylinder'
		function c:chart(lat, lon, height)
			return f(lat, lon, height)
		end
		-- TODO c:chartInv
		return c
	end)(),

	(function()
		-- gui vars
		local R = 2 / math.pi
		local lambda0 = 0
		local phi0 = 0
		local phi1 = 0
		-- symmath vars equivalent
		local Rvar = symmath.var'R'
		local lambda0var = symmath.var'lambda0'
		local phi0var = symmath.var'phi0'
		local phi1var = symmath.var'phi1'

		-- results
		local xval = Rvar * (lonradval - lambda0var) * symmath.cos(phi1var)
		local yval = Rvar * (latradval - phi0var)
		local zval = heightvar

		local f = symmath.export.Lua:toFunc{
			input = {
				-- args
				latvar, lonvar, heightvar,
				-- gui vars
				Rvar, lambda0var, phi0var, phi1var,
			},
			output = {xval, yval, zval},
		}

		local c = {}
		c.name = 'equirectangular'
		function c:chart(lat, lon, height)
			return f(lat, lon, height, R, lambda0, phi0, phi1)
		end
		return c
	end)(),

	(function()
		local azimuthalval = symmath.pi / 2 - latradval
		
		-- results
		local xval = -symmath.sin(lonradval + symmath.pi) * azimuthalval
		local yval = symmath.cos(lonradval + symmath.pi) * azimuthalval
		local zval = heightvar
	
		local f = symmath.export.Lua:toFunc{
			input = {
				-- args
				latvar, lonvar, heightvar,
				-- gui vars
			},
			output = {xval, yval, zval},
		}

		local c = {}
		c.name = 'azimuthalEquidistant'
		function c:chart(lat, lon, height)
			return f(lat, lon, height)
		end
		return c
	end)(),

	(function()
		local c = {}
		c.name = 'mollweide'
		function c:chart(lat, lon, height)
			local lonrad = math.rad(lon)
			local R = math.pi / 4
			local lambda = lonrad
			local lambda0 = 0	-- in degrees
			local latrad = math.rad(lat)
			local phi = latrad
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
			mollweidez = height
			if not math.isfinite(mollweidex) then mollweidex = 0 end
			if not math.isfinite(mollweidey) then mollweidey = 0 end
			if not math.isfinite(mollweidez) then mollweidez = 0 end
			return mollweidex, mollweidey, mollweidez
		end
		return c
	end)(),
}
for i=1,#charts do
	local chart = charts[i]
	charts[chart.name] = chart
end
return charts
