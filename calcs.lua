#!/usr/bin/env luajit
require 'ext'
require 'symmath'.setup{tostring='MathJax', MathJax={title='calcs'}}
local printbr = symmath.tostring.print

local x,y,z = vars('x','y','z')
local xs = table{x,y,z}
local h,theta,phi = vars('h','\\theta','\\phi')
local spheres = table{h,theta,phi}

local epsilon = var'\\epsilon'
printbr(epsilon,'= eccentricity')

local R = var'R'
printbr(R,'= equatorial radius')

-- https://codereview.stackexchange.com/questions/195933/convert-geodetic-coordinates-to-geocentric-cartesian
local N = var('N', {R, epsilon, theta})
local Ndef = N:eq(R / sqrt(1 - (epsilon * sin(theta))^2))
printbr(Ndef)

local dN_dTheta_def = Ndef:diff(theta)()
printbr(dN_dTheta_def)

local xdefs = table{
	x:eq( (N+h) * cos(theta) * cos(phi) ),
	y:eq( (N+h) * cos(theta) * sin(phi) ),
	z:eq( (N*(1 - epsilon^2) + h) * sin(theta) ),
}
for _,def in ipairs(xdefs) do printbr(def) end
printbr()

local r = var'r'
local r_def = (r^2):eq(x^2 + y^2 + z^2)
printbr(r_def)
r_def = r_def:subst(xdefs:unpack())()
printbr(r_def)
printbr()

local r2 = var'r_2'
local r2_def = (r2^2):eq(x^2 + y^2)
printbr(r2_def)
r2_def = r2_def:subst(xdefs:unpack())()
printbr(r2_def)
printbr()

local dxs_dspheres = Matrix:lambda({3,3}, function(i,j)
	return xdefs[i][2]
		--:subst(Ndef)
		:diff(spheres[j])()
end)()
printbr([[$\frac{\partial(x,y,z)}{\partial(h,\theta,\phi)} =$]], dxs_dspheres)

local dxs_dspheres_det = dxs_dspheres:det()() 
printbr([[$\frac{\partial|x,y,z|}{\partial|h,\theta,\phi|} =$]], dxs_dspheres_det)

local dxs_dspheres_det_h_eq_0 = dxs_dspheres_det:replace(h, 0)()
printbr([[$\frac{\partial|x,y,z|}{\partial|h,\theta,\phi|}_{h=0} =$]], dxs_dspheres_det_h_eq_0)

local dN_dTheta_var = var('dN_dTheta')
local _,code = dxs_dspheres_det_h_eq_0:replace(N:diff(theta), dN_dTheta_var):compile{N, dN_dTheta_var, epsilon, theta, h}
printbr()
printbr('det h=0 code:<br><pre>'..code..'</pre>')

local u,v = vars('u', 'v')
local intuv_def = Constant(1):integrate(v,0,1-u):integrate(u,0,1)
printbr(intuv_def,'=',intuv_def())
printbr()

local theta = var'\\theta'
local a_theta = var('a_\\theta')
local dutheta = var('d_{u,\\theta}')
local dvtheta = var('d_{v,\\theta}')
local theta_def = theta:eq(a_theta + dutheta * u + dvtheta * v)
printbr(theta_def)
printbr()

local sphere_int_def = dxs_dspheres_det_h_eq_0
	:replace(epsilon, 0)() -- hack for no flattening
	:integrate(v,0,1-u):integrate(u,0,1)


printbr(sphere_int_def)
sphere_int_def = sphere_int_def:subst(dN_dTheta_def)
printbr('=',sphere_int_def)
sphere_int_def = sphere_int_def:subst(theta_def)
printbr('=',sphere_int_def)

--[[ not yet working
sphere_int_def = sphere_int_def()
printbr('=',sphere_int_def)
--]]
