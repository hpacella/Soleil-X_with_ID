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
local Phase = {}
package.loaded['ebb.src.phase'] = Phase


local ast = require "ebb.src.ast"


------------------------------------------------------------------------------
--[[ Phase Types                                                          ]]--
------------------------------------------------------------------------------

local PhaseType = {}
PhaseType.__index = PhaseType
local PT = PhaseType
Phase.PhaseType = PhaseType

function PhaseType.New(params)
  local pt = setmetatable({
    read        = params.read,
    reduceop    = params.reduceop,
    write       = params.write,
    centered    = params.centered, -- i.e. centered
  }, PhaseType)
  return pt
end

-- does not pay attention to whether or not we're centered
function PhaseType:requiresExclusive()
  if self.write then return true end
  if self.read and self.reduceop then return true end
  if self.reduceop == 'multiop' then return true end
  return false
end

function PhaseType:isReadOnly()
  return self.read and not self.write and not self.reduceop
end

function PhaseType:isUncenteredReduction()
  return (not self.centered) and (not not self.reduceop)
end

function PhaseType:isCentered()
  return self.centered
end

function PhaseType:isWriting()
  return self.write
end

function PhaseType:reductionOp()
  return self.reduceop
end

function PhaseType:iserror()
  return not self.centered and self:requiresExclusive()
end

function PhaseType:__tostring()
  if self:iserror() then return 'ERROR' end
  if self:requiresExclusive() then return 'EXCLUSIVE' end

  local centered = ''
  if self.is_centered then centered = '_or_EXCLUSIVE' end

  if self.read then
    return 'READ' .. centered
  elseif self.reduceop then
    return 'REDUCE('..self.reduceop..')' .. centered
  end

  -- should never reach here
  return 'ERROR'
end

function PhaseType:join(rhs)
  local lhs = self

  local args = {
    read  = lhs.read  or rhs.read,
    write = lhs.write or rhs.write,
  }
  if lhs.centered and rhs.centered then args.centered = true end
  if lhs.reduceop or  rhs.reduceop then
    if lhs.reduceop and rhs.reduceop and lhs.reduceop ~= rhs.reduceop then
      args.reduceop = 'multiop'
    else
      args.reduceop = lhs.reduceop or rhs.reduceop
    end
  end

  return PhaseType.New(args)
end


------------------------------------------------------------------------------
--[[ Context:                                                             ]]--
------------------------------------------------------------------------------

local Context = {}
Context.__index = Context

function Context.new(env, diag)
  local ctxt = setmetatable({
    --env     = env,
    diag    = diag,
    fields  = {},
    globals = {},
    inserts = {},
    deletes = {},
    global_reduce = nil
  }, Context)
  return ctxt
end
function Context:error(ast, ...)
  self.diag:reporterror(ast, ...)
end

local function log_helper(ctxt, is_field, f_or_g, phase_type, node)
  -- Create an entry for the field or global
  local cache = ctxt.globals
  if is_field then cache = ctxt.fields end
  local lookup = cache[f_or_g]

  -- if this access was an error and is the first error
  if phase_type:iserror() then
    if not (lookup and lookup.phase_type:iserror()) then
      ctxt:error(node, 'Non-Exclusive WRITE')
    end
  end

  -- check if this field access conflicts with insertion
  if is_field then
    local insert = ctxt.inserts[f_or_g:Relation()]
    if insert then
      local insertfile = insert.last_access.filename
      local insertline = insert.last_access.linenumber
      ctxt:error(node,
        'Cannot access field '..f_or_g:FullName()..' while inserting\n('..
        insertfile..':'..insertline..') into relation '..
        f_or_g:Relation():Name())
    end
  end

  -- first access
  if not lookup then
    lookup = {
      phase_type = phase_type,
      last_access = node,
    }
    cache[f_or_g] = lookup
  -- later accesses
  else
    local join_type = lookup.phase_type:join(phase_type)
    -- if first error, then...
    if join_type:iserror() and
       not (phase_type:iserror() or lookup.phase_type:iserror())
    then
      local lastfile = lookup.last_access.filename
      local lastline = lookup.last_access.linenumber
      local g_opt = ' for Global'
      if is_field then g_opt = '' end
      ctxt:error(node, tostring(phase_type)..' Phase'..g_opt..' is'..
                                             ' incompatible with\n'..
                       lastfile..':'..lastline..': '..
                       tostring(lookup.phase_type)..' Phase'..g_opt..'\n')
    end
    lookup.phase_type  = join_type
    lookup.last_access = node
  end

  -- check if this field access conflicts with deletion
  -- (deletes count as write accesses, for all the relation's fields)
  if is_field then
    if ctxt.deletes[f_or_g:Relation()] then
      local exclWrite = PhaseType.New{ write = true, centered = true }
      if lookup.phase_type:join(exclWrite):iserror() then
        ctxt:error(node, 'Access to field '..f_or_g:FullName()..
                         ' conflicts with delete from relation '..
                         f_or_g:Relation():Name())
      end
    end
  end

  -- check if more than one globals need to be reduced
  if not is_field and phase_type:isUncenteredReduction() then
    local reduce_entry = ctxt.global_reduce
    if reduce_entry and lookup ~= reduce_entry then
      ctxt:error(node, 'Cannot reduce more than one global in a function.  '..
                       'Previously tried to reduce at '..
                       lookup.last_access.filename..':'..
                       lookup.last_access.linenumber..'\n')
    else
      ctxt.global_reduce = lookup
    end
  end
end

function Context:logfield(field, phase_type, node)
  log_helper(self, true, field, phase_type, node)
end

function Context:logglobal(global, phase_type, node)
  log_helper(self, false, global, phase_type, node)
end

function Context:loginsert(relation, node)
  -- check that we don't also delete from the relation
  -- (implicit: can only delete from the relation being mapped over, and can't
  --  insert into that relation)

  -- check that none of the relation's fields have been accessed
  for field,record in pairs(self.fields) do
    if relation == field:Relation() then
      local insertfile = node.filename
      local insertline = node.linenumber
      self:error(record.last_access,
        'Cannot access field '..field:FullName()..' while inserting\n('..
        insertfile..':'..insertline..') into relation '..relation:Name())
      return
    end
  end

  -- check that the relation being mapped over isn't being inserted into
  if self.relation == relation then
    self:error(node, 'Cannot insert into relation '..relation:Name()..
               ' while mapping over it')
  end

  -- check that this is the only insert for this relation
  if self.inserts[relation] then
    self:error(node, 'Cannot insert into relation '..relation:Name()..' twice')
  end

  -- check that the coupling field is set through a centered access
  if relation:isCoupled() then
    local couplingFld = relation:CouplingField()
    for i,name in ipairs(node.record.names) do
      if name == couplingFld:Name() then
        if not node.record.exprs[i].is_centered then
          self:error(node, 'Coupling field "'..name..'" must be set '..
                           'through a centered access')
        end
      end
    end
  end

  -- register insertion
  self.inserts[relation] = {
    last_access = node
  }
end

function Context:logdelete(relation, node)
  -- check that the key is centered
  -- (happens in type-checking pass)

  -- check that the relation isn't also being inserted into
  -- (implicit: can only delete from the relation being mapped over, and can't
  --  insert into that relation)

  -- check for field accesses conflicting with deletion
  -- (deletes count as write accesses, for all the relation's fields)
  local exclWrite = PhaseType.New{ write = true, centered = true }
  for _,f in ipairs(relation._fields) do
    local fldAccess = self.fields[f]
    if fldAccess and fldAccess.phase_type:join(exclWrite):iserror() then
      self:error(node, 'Access to field '..f:FullName()..
                       ' conflicts with delete from relation '..
                       relation:Name())
    end
  end

  -- check that this is the only delete for this function
  -- since only the relation mapped over can possibly be deleted from
  -- this check suffices
  if self.deletes[relation] then
    self:error(node,
      'Temporary: can only have one delete statement per function')
  end

  -- register the deletion
  self.deletes[relation] = {
    last_access = node
  }
end

function Context:dumpFieldTypes()
  local res = {}
  for k,record in pairs(self.fields) do
    res[k] = record.phase_type
  end
  return res
end

function Context:dumpGlobalTypes()
  local res = {}
  for k, record in pairs(self.globals) do
    res[k] = record.phase_type
  end
  return res
end

function Context:dumpInserts()
  local ret = {}
  for relation,record in pairs(self.inserts) do
    -- ASSUME THERE IS ONLY ONE INSERT
    ret[relation] = {record.last_access} -- list of AST nodes for inserts
  end
  if next(ret) == nil then return nil end -- return nil if nothing
  return ret
end

function Context:dumpDeletes()
  local ret = {}
  for relation,record in pairs(self.deletes) do
    -- ASSUME UNIQUE INSERT PER FUNCTION
    ret[relation] = {record.last_access} -- list of AST nodes for deletes
  end
  if next(ret) == nil then return nil end -- return nil if nothing
  return ret
end

------------------------------------------------------------------------------
--[[ Phase Pass:                                                          ]]--
------------------------------------------------------------------------------

function Phase.phasePass(ufunc_ast)
  local env  = terralib.newenvironment(nil)
  local diag = terralib.newdiagnostics()
  local ctxt = Context.new(env, diag)

  -- record the relation being mapped over
  ctxt.relation = ufunc_ast.relation

  ufunc_ast:phasePass(ctxt)
  diag:finishandabortiferrors("Errors during phasechecking Ebb", 1)

  local field_use   = ctxt:dumpFieldTypes()
  local global_use  = ctxt:dumpGlobalTypes()
  local inserts     = ctxt:dumpInserts()
  local deletes     = ctxt:dumpDeletes()

  return {
    field_use   = field_use,
    global_use  = global_use,
    inserts     = inserts,
    deletes     = deletes,
  }
end


------------------------------------------------------------------------------
--[[ AST Nodes:                                                           ]]--
------------------------------------------------------------------------------

ast.NewInertPass('phasePass')




function ast.FieldWrite:phasePass (ctxt)
  -- We intentionally skip over the Field Access here...
  self.fieldaccess.key:phasePass(ctxt)
  if self.fieldaccess:is(ast.FieldAccessIndex) then
    self.fieldaccess.index:phasePass(ctxt)
    if self.fieldaccess.index2 then
        self.fieldaccess.index2:phasePass(ctxt)
    end
  end

  local pargs    = { centered = self.fieldaccess.key.is_centered }
  if self.reduceop then
    pargs.reduceop = self.reduceop
  else
    pargs.write    = true
  end
  local ptype    = PhaseType.New(pargs)

  local field    = self.fieldaccess.field
  ctxt:logfield(field, ptype, self)

  self.exp:phasePass(ctxt)
end

function ast.FieldAccess:phasePass (ctxt)
  -- if we got here, it wasn't through a write or reduce use
  self.key:phasePass(ctxt)
  local ptype = PhaseType.New {
    centered = self.key.is_centered,
    read = true
  }
  ctxt:logfield(self.field, ptype, self)
end

function ast.FieldAccessIndex:phasePass (ctxt)
  -- if we got here, it wasn't through a write or reduce use
  self.key:phasePass(ctxt)
  self.index:phasePass(ctxt)
  if (self.index2) then
      self.index2:phasePass(ctxt)
  end

  local ptype = PhaseType.New {
    centered = self.key.is_centered,
    read = true
  }
  ctxt:logfield(self.field, ptype, self)
end



function ast.Call:phasePass (ctxt)
  for i,p in ipairs(self.params) do
    -- Terra Funcs may write or do other nasty things...
    if self.func.is_a_terra_func and p:is(ast.FieldAccess) then
      p.key:phasePass()

      local ptype = PhaseType.New {
        write = true, read = true, -- since we can't tell for calls!
        centered = p.key.is_centered,
      }
      ctxt:logfield(p.field, ptype, p)
    elseif self.func.is_a_terra_func and p:is(ast.Global) then
      self:error(p, 'Unable to verify that global field will not be '..
                    'written by external function call.')
    else
      p:phasePass(ctxt)
    end
  end
end


function ast.GlobalReduce:phasePass(ctxt)
  if self.global:is(ast.GlobalIndex) then
    self.global.index:phasePass(ctxt)
    if self.global.index2 then
        self.global.index2:phasePass(ctxt)
    end
  end
  local ptype = PhaseType.New { reduceop = self.reduceop }
  local global = self.global.global
  ctxt:logglobal(global, ptype, self)

  self.exp:phasePass(ctxt)
end

function ast.Global:phasePass (ctxt)
  -- if we got here, it wasn't through a write or reduce use
  ctxt:logglobal(self.global, PhaseType.New { read = true } , self)
end

function ast.GlobalIndex:phasePass (ctxt)
  -- if we got here, it wasn't through a write or reduce use
  self.index:phasePass(ctxt)
  if self.index2 then
      self.index2:phasePass(ctxt)
  end
  self.base:phasePass(ctxt)
  ctxt:logglobal(self.global, PhaseType.New { read = true } , self)
end


function ast.Where:phasePass(ctxt)
  -- Which field is the index effectively having us read?
  --local keyfield = self.relation:GroupedKeyField()
  local offfield = self.relation:_INTERNAL_GroupedOffset()
  local lenfield = self.relation:_INTERNAL_GroupedLength()
  --ctxt:logfield(keyfield, PhaseType.New{ read = true }, self)
  -- NOTE: I'm PRETTY SURE that the keyfield isn't being touched...
  ctxt:logfield(offfield, PhaseType.New{ read = true }, self)
  ctxt:logfield(lenfield, PhaseType.New{ read = true }, self)

  self.key:phasePass(ctxt)
end

function ast.GenericFor:phasePass(ctxt)
  self.set:phasePass(ctxt)
  -- assert(self.set.node_type:isquery())

  -- deal with any field accesses implied by projection
  local rel = self.set.node_type.relation
  for i,p in ipairs(self.set.node_type.projections) do
    local field = rel[p]
    ctxt:logfield(field, PhaseType.New { read = true }, self)

    rel = field:Type().relation
  end

  self.body:phasePass(ctxt)
end

--------------------------------
-- handle inserts and deletes

function ast.InsertStatement:phasePass(ctxt)
  self.record:phasePass(ctxt)
  self.relation:phasePass(ctxt)

  local relation = self.relation.node_type.value

  -- log the insertion
  ctxt:loginsert(relation, self)
end

function ast.DeleteStatement:phasePass(ctxt)
  self.key:phasePass(ctxt)

  local relation = self.key.node_type.relation

  -- log the delete
  ctxt:logdelete(relation, self)
end
