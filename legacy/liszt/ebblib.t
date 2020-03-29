-- The MIT License (MIT)
--
-- Copyright (c) 2015 Stanford University.
-- All rights reserved.
--
-- Permission is hereby granted, free of charge, to any person obtaining a
-- copy of this software and associated documentation files (the "Software"),
-- to deal in the Software without restriction, including without limitation
-- the rights to use, copy, modify, merge, publish, distribute, sublicense,
-- and/or sell copies of the Software, and to permit persons to whom the
-- Software is furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included
-- in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
-- DEALINGS IN THE SOFTWARE.
local L = {}
package.loaded["ebblib"] = L

-------------------------------------------------------------------------------
--[[    Types                                                              ]]--
-------------------------------------------------------------------------------

local T = require 'ebb.src.types'

L.int           = T.int
L.int64         = T.int64
L.uint          = T.uint
L.uint64        = T.uint64
L.bool          = T.bool
L.float         = T.float
L.double        = T.double

L.vector        = T.vector
L.matrix        = T.matrix
L.key           = T.key

for _,tchar in ipairs({ 'i', 'f', 'd', 'b' }) do
  for n=2,4 do
    n = tostring(n)
    L['vec'..n..tchar] = T['vec'..n..tchar]
    L['mat'..n..tchar] = T['mat'..n..tchar]
    for m=2,4 do
      local m = tostring(m)
      L['mat'..n..'x'..m..tchar] = T['mat'..n..'x'..m..tchar]
    end
  end
end


-------------------------------------------------------------------------------
--[[    Builtins                                                           ]]--
-------------------------------------------------------------------------------

local B       = require "ebb.src.builtins"
L.Affine          = B.Affine

L.print           = B.print
L.assert          = B.assert
L.rand            = B.rand

L.dot             = B.dot
L.times           = B.times
L.cross           = B.cross
L.length          = B.length

L.id              = B.id
L.xid             = B.xid
L.yid             = B.yid
L.zid             = B.zid

L.UNSAFE_ROW      = B.UNSAFE_ROW

L.acos            = B.acos
L.asin            = B.asin
L.atan            = B.atan
L.cbrt            = B.cbrt
L.ceil            = B.ceil
L.cos             = B.cos
L.fabs            = B.fabs
L.floor           = B.floor
L.fmax            = B.fmax
L.fmin            = B.fmin
L.imax            = B.imax
L.imin            = B.imin
L.fmod            = B.fmod
L.log             = B.log
L.pow             = B.pow
L.sin             = B.sin
L.sqrt            = B.sqrt
L.tan             = B.tan


-------------------------------------------------------------------------------
--[[    The Rest                                                           ]]--
-------------------------------------------------------------------------------

local Pre     = require "ebb.src.prelude"
L.Global          = Pre.NewGlobal
L.Constant        = Pre.NewConstant
L.Macro           = Pre.NewMacro
L.CPU             = Pre.CPU
L.GPU             = Pre.GPU
L.SetDefaultProcessor = Pre.SetDefaultProcessor
L.GetDefaultProcessor = Pre.GetDefaultProcessor

local R       = require "ebb.src.relations"
L.NewRelation     = R.NewRelation
L.is_loader       = R.is_loader
L.is_dumper       = R.is_dumper
L.NewLoader       = R.NewLoader
L.NewDumper       = R.NewDumper

-- resolve circular dependency problem
T.is_relation     = R.is_relation

local F = require "ebb.src.functions"

L.is_function     = F.is_function
L.is_builtin      = B.is_builtin
L.is_relation     = R.is_relation
L.is_field        = R.is_field
L.is_subset       = R.is_subset
L.is_global       = Pre.is_global
L.is_constant     = Pre.is_constant
L.is_macro        = Pre.is_macro
L.is_type         = T.istype
