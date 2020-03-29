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

-- location to put all C includes
-- the rest of the compiler should just require this file

local ffi = require 'ffi'

local enum_list = {
  {str='SEEK_SET',ctype='int',ttype=int},
  {str='SEEK_CUR',ctype='int',ttype=int},
  {str='CLOCKS_PER_SEC',ctype='uint64_t',ttype=uint64},
  {str="INT_MIN",ctype='int32_t',ttype=int32},
  {str="INT_MAX",ctype='int32_t',ttype=int32},
  {str="ULONG_MAX",ctype='uint64_t',ttype=uint64},
  {str="FLT_MIN",ctype='float',ttype=float},
  {str="FLT_MAX",ctype='float',ttype=float},
  {str="DBL_MIN",ctype='double',ttype=double},
  {str="DBL_MAX",ctype='double',ttype=double},
  {str="STDERR_FILENO",ctype='int',ttype=int},
  {str="RAND_MAX",ctype='double',ttype=double},
}



-- inject a bit of code for extracting enum values
local enum_c_define = [[
void ebb_c_terra_enum_define_helper(void **out) {
]]
for i,enum in ipairs(enum_list) do
  enum_c_define = enum_c_define ..
  '*(('..enum.ctype..'*)(out['..tostring(i-1)..'])) = '..enum.str..';\n'
end
enum_c_define = enum_c_define .. '}\n'


-- system timer
local sys_time = [[
#include <sys/time.h>
double get_wall_time(){
  struct timeval time;
  if (gettimeofday(&time,NULL)){
    return 0;
  }
  return (double)time.tv_sec + (double)time.tv_usec * .000001;
}
]]


-- Load the blob of C defines
local c_blob = terralib.includecstring(
[[

//#include "../deprecated_runtime/src/lmeshloader.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <float.h>
#include <limits.h>
#include <math.h>
#include <time.h>
#include <execinfo.h>
#include <unistd.h>

FILE * __sew_get__stdout() { return stdout; }
FILE * __sew_get__stdin()  { return stdin; }
FILE * __sew_get__stderr() { return stderr; }

]]..
enum_c_define ..
sys_time
)

rawset(c_blob, 'stdout', c_blob.__sew_get__stdout())
rawset(c_blob, 'stdin',  c_blob.__sew_get__stdin())
rawset(c_blob, 'stderr', c_blob.__sew_get__stderr())

rawset(c_blob, 'assert', macro(function(test)
  local filename = test.tree.filename
  local linenumber = test.tree.linenumber

  return quote
    if not test then
      c_blob.fprintf(c_blob.stderr,
        [filename..':'..linenumber..': Terra Assertion Failed!\n'])
      c_blob.exit(1)
    end
  end
end))

rawset(c_blob, 'safemalloc', macro(function()
  error('safemalloc may not be called inside of Terra code')
end,
function( ttype, N )
  N = N or 1
  local ptr = terralib.cast( &ttype,
                             c_blob.malloc( N * terralib.sizeof(ttype) ))
  ffi.gc( ptr, c_blob.free )
  return ptr
end))


-- now extract the enum constants
do
  -- allocate array and each entry space
  local out_arr = terralib.cast(&&opaque,
    c_blob.malloc(#enum_list * terralib.sizeof(&opaque)))
  local enum_values = {}
  for i,enum in ipairs(enum_list) do
    enum_values[i] = terralib.cast(&enum.ttype,
      c_blob.malloc(terralib.sizeof(enum.ttype)))
    out_arr[i-1] = enum_values[i]
  end

  -- execute our extraction function
  c_blob.ebb_c_terra_enum_define_helper(out_arr)

  -- now read out the values and store them in the cblob
  for i,enum in ipairs(enum_list) do
    c_blob[enum.str] = enum_values[i][0] -- [0] derefrences the pointer
    c_blob.free(enum_values[i])
  end
  c_blob.free(out_arr)
end






package.loaded["ebb.src.c"] = c_blob
return c_blob
