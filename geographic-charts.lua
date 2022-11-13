--[[
I use these often enough that they are going to go into a library soon enough
2D charts will be xy coordinates, z will be for height
3D charts will also be oriented for default view in the xy plane (i.e. y+ will be north pole, z+ will be prime meridian)
--]]
local charts = {
	(function()
		local c = {}
		
		c.name = 'WGS84'
		
		-- specific to WGS84:
		local inverseFlattening = 298.257223563
		c.inverseFlattening = inverseFlattening
		local eccentricitySquared = (2 * inverseFlattening - 1) / (inverseFlattening * inverseFlattening)
		c.eccentricitySquared = eccentricitySquared
		
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

		-- |d(x,y,z)/d(h,theta,phi)| for h=0
		function c:dx_dsphere_det_h_eq_0(lat) 
			local theta = math.rad(lat)		-- spherical inclination angle (not azumuthal theta)
			local sinTheta = math.sin(theta)
			local cosTheta = math.cos(theta)
			
			local h = 0
			local N = self:calc_N(sinTheta, self.a, eccentricitySquared)
			local dN_dTheta = calc_dN_dTheta(sinTheta, cosTheta, self.a, eccentricitySquared)
			local cosTheta2 = cosTheta * cosTheta
			return -N * (
				N * cosTheta 
				+ eccentricitySquared * cosTheta2 * N * cosTheta
				+ eccentricitySquared * cosTheta2 * dN_dTheta * sinTheta
			)
		end

		-- returns x,y,z in meters
		-- lat = [-90,90] in degrees
		-- lon = [-180,180] in degrees
		-- height >= 0 in meters
		-- returns: x,y,z in meters
		function c:chart(lat, lon, height)
			local phi = math.rad(lon)		-- spherical phi
			local theta = math.rad(lat)		-- spherical inclination angle (not azumuthal theta)
			local cosTheta = math.cos(theta)
			local sinTheta = math.sin(theta)
			
			local N = self:calc_N(sinTheta, self.a, eccentricitySquared)
			
			local NPlusH = N + height
			return 
				NPlusH * cosTheta * math.cos(phi),
				NPlusH * cosTheta * math.sin(phi),
				(N * (1 - eccentricitySquared) + height) * sinTheta
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
			local height = NPlusH - self:calc_N(math.sin(theta), self.a, eccentricitySquared)

			-- lat, lon, height:
			return 
				math.deg(theta),
				(math.deg(phi) + 180) % 360 - 180, 
				height
		end
	
		return c
	end)(),
}
for i=1,#charts do
	local chart = charts[i]
	charts[chart.name] = chart
end
return charts
