--locals
local developer = GetConVar("developer")
local operations = STENCIL_CORE.Operations
local parameterized_operations = STENCIL_CORE.ParameterizedOperations
local render_SetColorModulation = render.SetColorModulation

local compiled_code_header = [[--automatically generated by [E2] Stencil Core
local draw_entities = STENCIL_CORE._CompiledDrawEntities
local render = render]]

--local tables
local cached_types = {
	table = true,
}

local deserialize_functions = {
	boolean = tostring,
	number = tostring,
	table = function(value) return "Color(" .. value.r .. ", " .. value.g .. ", " .. value.b .. ", " .. value.a .. ")" end,
}

local required_header_operations_static = {
	clear_stencil = true,
	enabled = true,
	set_compare = STENCIL_ALWAYS,
	set_fail_operation = STENCIL_KEEP,
	set_occluded_operation = STENCIL_KEEP,
	set_pass_operation = STENCIL_KEEP,
	set_reference_value = 1,
	set_test_mask = 255,
	set_write_mask = 255,
}

local write_operations = {
	clear = true,
	draw = true,
	run = true,
}

--local functions
local function name_source(stencil)
	local ply = stencil.Owner
	
	if ply:IsValid() then return "stencil_core[" .. stencil.ChipIndex .. "(" .. tostring(ply:EntIndex()) .. "/" .. ply:UserID() .. ")-" .. stencil.Index .. "]"
	else return "stencil_core[" .. stencil.ChipIndex .. "(unknown)-" .. stencil.Index .. "]" end
end

local function serialize_value(value) return deserialize_functions[type(value)](value) end

--stencil functions
function STENCIL_CORE:CompileStencil(stencil)
	local code = ""
	local code_header = compiled_code_header
	local entity_layers = stencil.EntityLayers
	local in_header = true
	local instructions = table.Copy(stencil.Instructions)
	local instructions_count = #instructions
	local parameter_line = ""
	local parameterized_instructions = table.Copy(stencil.ParameterizedIndices)
	local required_header_operations = table.Copy(required_header_operations_static)
	local trimming --1 more than the index of the last operation that writes to the stencil
	local while_index = 1
	
	--build header and footer instructions
	while while_index <= instructions_count do --you can't adjust the end of a for loop while it's running :(
		local instruction = instructions[while_index]
		local operation = instruction[1]
		--local operation_code = operations[instruction[1]]
		--local value = instruction[2]
		
		if in_header then
			if write_operations[operation] then
				local missing_operations = table.Count(required_header_operations)
				in_header = false
				instructions_count = instructions_count + missing_operations
				
				for parameter_index, instruction_index in ipairs(parameterized_instructions) do
					--correct the parameterized operations indices to account for the newly inserted missing operations
					if instruction_index >= while_index then parameterized_instructions[parameter_index] = instruction_index + missing_operations end
				end
				
				for required_operation, default_value in pairs(required_header_operations) do
					--insert missing operations at the currently itterated index
					table.insert(instructions, while_index, {required_operation, default_value})
				end
				
				--correct the index for trimming and stuff
				while_index = while_index + missing_operations
			else required_header_operations[operation] = nil end
		elseif write_operations[operation] then trimming = while_index + 1 end
		
		while_index = while_index + 1
	end
	
	if trimming then
		--delete unused instructions
		for index = trimming, #instructions do instructions[index] = nil end
	end
	
	--insert the operation to turn off the stencil
	table.insert(instructions, {"enabled", false})
	
	--write the code
	for index, instruction in ipairs(instructions) do
		local operation = instruction[1]
		local value = instruction[2]
		
		if parameterized_operations[operation] then
			if cached_types[type(value)] then
				code = code .. "\n\t" .. string.gsub(operations[operation], "%$", "local_" .. index) or operations[operation]
				code_header = code_header .. "\nlocal local_" .. index .. " = " .. serialize_value(value)
			else code = code .. "\n\t" .. string.gsub(operations[operation], "%$", serialize_value(value)) or operations[operation] end
		else code = code .. "\n\t" .. operations[operation] end
	end
	
	--parameterized stuff
	--[[ POST: implement parameterized stuff
	if parameterized_instructions[1] ~= nil then
		local parameter_count = #parameterized_instructions
		
		for index in ipairs(parameterized_instructions) do
			if index == parameter_count then parameter_line = parameter_line .. "local_" .. parameterized_instructions[index]
			else parameter_line = parameter_line .. "local_" .. parameterized_instructions[index] .. ", " end
		end
	end --]]
	
	--create the draw_entities function
	function self._CompiledDrawEntities(layer_index)
		local color_changed = false
		local entities = entity_layers[layer_index]
		
		if entities then
			for index, entity in ipairs(entities) do
				if entity:IsValid() and not entity:IsDormant() then
					local color = entity:GetColor()
					local r, g, b = color.r, color.g, color.b
					
					if r ~= 255 or g ~= 255 or b ~= 255 then
						color_changed = true
						
						render_SetColorModulation(r / 255, g / 255, b / 255)
					elseif color_changed then
						color_changed = false
						
						render_SetColorModulation(1, 1, 1)
					end
					
					entity:DrawModel()
				end
			end
			
			if color_changed then render_SetColorModulation(1, 1, 1) end
		end
	end
	
	--put the header and code body together
	code = code_header .. "\nreturn function(" .. parameter_line .. ")" .. code .. "\nend"
	local compiled_code = CompileString(code, name_source(stencil))
	local render_function = compiled_code()
	
	if developer:GetInt() >= 2 then MsgC(color_white, code, "\n") end
	
	self._CompiledDrawEntities = nil
	stencil.Compiled = render_function and true or false
	stencil.RenderFunction = render_function
end