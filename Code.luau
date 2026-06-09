-- [[ SETUP ]] --

-- // the mask and templates

local mh
local templates

do
	local function Decode(str)
		local StringLength = #str

		-- Base64 decoding
		do
			local decoder = {}
			for b64code, char in pairs(('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/='):split('')) do
				decoder[char:byte()] = b64code-1
			end
			local n = StringLength
			local t,k = table.create(math.floor(n/4)+1),1
			local padding = str:sub(-2) == '==' and 2 or str:sub(-1) == '=' and 1 or 0
			for i = 1, padding > 0 and n-4 or n, 4 do
				local a, b, c, d = str:byte(i,i+3)
				local v = decoder[a]*0x40000 + decoder[b]*0x1000 + decoder[c]*0x40 + decoder[d]
				t[k] = string.char(bit32.extract(v,16,8),bit32.extract(v,8,8),bit32.extract(v,0,8))
				k = k + 1
			end
			if padding == 1 then
				local a, b, c = str:byte(n-3,n-1)
				local v = decoder[a]*0x40000 + decoder[b]*0x1000 + decoder[c]*0x40
				t[k] = string.char(bit32.extract(v,16,8),bit32.extract(v,8,8))
			elseif padding == 2 then
				local a, b = str:byte(n-3,n-2)
				local v = decoder[a]*0x40000 + decoder[b]*0x1000
				t[k] = string.char(bit32.extract(v,16,8))
			end
			str = table.concat(t)
		end

		local Position = 1
		local function Parse(fmt)
			local Values = {string.unpack(fmt,str,Position)}
			Position = table.remove(Values)
			return table.unpack(Values)
		end

		local Settings = Parse('B')
		local Flags = Parse('B')
		Flags = {
			--[[ValueIndexByteLength]] bit32.extract(Flags,6,2)+1,
			--[[InstanceIndexByteLength]] bit32.extract(Flags,4,2)+1,
			--[[ConnectionsIndexByteLength]] bit32.extract(Flags,2,2)+1,
			--[[MaxPropertiesLengthByteLength]] bit32.extract(Flags,0,2)+1,
			--[[Use Double instead of Float]] bit32.band(Settings,0b1) > 0
		}

		local ValueFMT = ('I'..Flags[1])
		local InstanceFMT = ('I'..Flags[2])
		local ConnectionFMT = ('I'..Flags[3])
		local PropertyLengthFMT = ('I'..Flags[4])

		local ValuesLength = Parse(ValueFMT)
		local Values = table.create(ValuesLength)
		local CFrameIndexes = {}

		local ValueDecoders = {
			--!!Start
			[1] = function(Modifier)
				return Parse('s'..Modifier)
			end,
			--!!Split
			[2] = function(Modifier)
				return Modifier ~= 0
			end,
			--!!Split
			[3] = function()
				return Parse('d')
			end,
			--!!Split
			[4] = function(_,Index)
				table.insert(CFrameIndexes,{Index,Parse(('I'..Flags[1]):rep(3))})
			end,
			--!!Split
			[5] = {CFrame.new,Flags[5] and 'dddddddddddd' or 'ffffffffffff'},
			--!!Split
			[6] = {Color3.fromRGB,'BBB'},
			--!!Split
			[7] = {BrickColor.new,'I2'},
			--!!Split
			[8] = function(Modifier)
				local len = Parse('I'..Modifier)
				local kpts = table.create(len)
				for i = 1,len do
					kpts[i] = ColorSequenceKeypoint.new(Parse('f'),Color3.fromRGB(Parse('BBB')))
				end
				return ColorSequence.new(kpts)
			end,
			--!!Split
			[9] = function(Modifier)
				local len = Parse('I'..Modifier)
				local kpts = table.create(len)
				for i = 1,len do
					kpts[i] = NumberSequenceKeypoint.new(Parse(Flags[5] and 'ddd' or 'fff'))
				end
				return NumberSequence.new(kpts)
			end,
			--!!Split
			[10] = {Vector3.new,Flags[5] and 'ddd' or 'fff'},
			--!!Split
			[11] = {Vector2.new,Flags[5] and 'dd' or 'ff'},
			--!!Split
			[12] = {UDim2.new,Flags[5] and 'di2di2' or 'fi2fi2'},
			--!!Split
			[13] = {Rect.new,Flags[5] and 'dddd' or 'ffff'},
			--!!Split
			[14] = function()
				local flags = Parse('B')
				local ids = {"Top","Bottom","Left","Right","Front","Back"}
				local t = {}
				for i = 0,5 do
					if bit32.extract(flags,i,1)==1 then
						table.insert(t,Enum.NormalId[ids[i+1]])
					end
				end
				return Axes.new(unpack(t))
			end,
			--!!Split
			[15] = function()
				local flags = Parse('B')
				local ids = {"Top","Bottom","Left","Right","Front","Back"}
				local t = {}
				for i = 0,5 do
					if bit32.extract(flags,i,1)==1 then
						table.insert(t,Enum.NormalId[ids[i+1]])
					end
				end
				return Faces.new(unpack(t))
			end,
			--!!Split
			[16] = {PhysicalProperties.new,Flags[5] and 'ddddd' or 'fffff'},
			--!!Split
			[17] = {NumberRange.new,Flags[5] and 'dd' or 'ff'},
			--!!Split
			[18] = {UDim.new,Flags[5] and 'di2' or 'fi2'},
			--!!Split
			[19] = function()
				return Ray.new(Vector3.new(Parse(Flags[5] and 'ddd' or 'fff')),Vector3.new(Parse(Flags[5] and 'ddd' or 'fff')))
			end
			--!!End
		}

		for i = 1,ValuesLength do
			local TypeAndModifier = Parse('B')
			local Type = bit32.band(TypeAndModifier,0b11111)
			local Modifier = (TypeAndModifier - Type) / 0b100000
			local Decoder = ValueDecoders[Type]
			if type(Decoder)=='function' then
				Values[i] = Decoder(Modifier,i)
			else
				Values[i] = Decoder[1](Parse(Decoder[2]))
			end
		end

		for i,t in pairs(CFrameIndexes) do
			Values[t[1]] = CFrame.fromMatrix(Values[t[2]],Values[t[3]],Values[t[4]])
		end

		local InstancesLength = Parse(InstanceFMT)
		local Instances = {}
		local NoParent = {}

		for i = 1,InstancesLength do
			local ClassName = Values[Parse(ValueFMT)]
			local obj
			local MeshPartMesh,MeshPartScale
			if ClassName == "UnionOperation" then
				obj = DecodeUnion(Values,Flags,Parse)
				obj.UsePartColor = true
			elseif ClassName:find("Script") then
				obj = Instance.new("Folder")
				Script(obj,ClassName=='ModuleScript')
			elseif ClassName == "MeshPart" then
				obj = Instance.new("Part")
				MeshPartMesh = Instance.new("SpecialMesh")
				MeshPartMesh.MeshType = Enum.MeshType.FileMesh
				MeshPartMesh.Parent = obj
			else
				obj = Instance.new(ClassName)
			end
			local Parent = Instances[Parse(InstanceFMT)]
			local PropertiesLength = Parse(PropertyLengthFMT)
			local AttributesLength = Parse(PropertyLengthFMT)
			Instances[i] = obj
			for i = 1,PropertiesLength do
				local Prop,Value = Values[Parse(ValueFMT)],Values[Parse(ValueFMT)]

				-- ok this looks awful
				if MeshPartMesh then
					if Prop == "MeshId" then
						MeshPartMesh.MeshId = Value
						continue
					elseif Prop == "TextureID" then
						MeshPartMesh.TextureId = Value
						continue
					elseif Prop == "Size" then
						if not MeshPartScale then
							MeshPartScale = Value
						else
							MeshPartMesh.Scale = Value / MeshPartScale
						end
					elseif Prop == "MeshSize" then
						if not MeshPartScale then
							MeshPartScale = Value
							MeshPartMesh.Scale = obj.Size / Value
						else
							MeshPartMesh.Scale = MeshPartScale / Value
						end
						continue
					end
				end

				obj[Prop] = Value
			end
			if MeshPartMesh then
				if MeshPartMesh.MeshId=='' then
					if MeshPartMesh.TextureId=='' then
						MeshPartMesh.TextureId = 'rbxasset://textures/meshPartFallback.png'
					end
					MeshPartMesh.Scale = obj.Size
				end
			end
			for i = 1,AttributesLength do
				obj:SetAttribute(Values[Parse(ValueFMT)],Values[Parse(ValueFMT)])
			end
			if not Parent then
				table.insert(NoParent,obj)
			else
				obj.Parent = Parent
			end
		end

		local ConnectionsLength = Parse(ConnectionFMT)
		for i = 1,ConnectionsLength do
			local a,b,c = Parse(InstanceFMT),Parse(ValueFMT),Parse(InstanceFMT)
			Instances[a][Values[b]] = Instances[c]
		end

		return NoParent
	end


	mh = Decode('AAC5IQRUb29sIQROYW1lIQpTdG9uZSBNYXNrIQpXb3JsZFBpdm90BKytriEITWVzaFBhcnQhBkhhbmRsZSEGQ0ZyYW1lBA+triEITWF0ZXJpYWwDAAAAAAAAkUAhC09yaWVudGF0aW9uCgAAtMIAAAAAAAAAACEIUG9zaXRpb24KGlumwWTynD9JY/nBIQhSb3RhdGlv'
		..'biEEU2l6ZQr1bkI/Y4B8PgNKoD8hBk1lc2hJZCEXcmJ4YXNzZXRpZDovLzQ1NDAwNDc0MjEhCE1lc2hTaXplCl5XpkADBdg/VSEJQSEJVGV4dHVyZUlEIRdyYnhhc3NldGlkOi8vNDU0MDA0NzQ2NCEFSW5uZXIhCkJyaWNrQ29sb3IHxwAEH62uIQVDb2xvcgZjX2IK'
		..'IFumwVMrnT8/HfnBCuFlPT+OhEo+/LKZPyEXcmJ4YXNzZXRpZDovLzQ1NDAwNTIxMjkKiwiiQPJBrT8NfgNBIQpNYW51YWxXZWxkIQJDMASvsLEhAkMxBLKwsSEFUGFydDAhBVBhcnQxBCutrgokW6bBZPKcP4Y1+cEK9W5CP+3TYj4DSqA/IRdyYnhhc3NldGlkOi8v'
		..'NDU0MDA1MDE0MQpeV6ZAKA7CP1UhCUEEs7CxIQVPdXRlcgQyra4KYkylwaAGwz94afnBCks03z47YYs+uNo0PyEXcmJ4YXNzZXRpZDovLzQ1NDAwNDg5NzgKjPQ+QNx77j9huZpAIRdyYnhhc3NldGlkOi8vNDU0MDA0OTAwMQS0sLEhBlNwaWtlcwQ6ra4KIFumwYr7'
		..'rz/OMPXBCvAhgD9aLGg/C31nPyEMVHJhbnNwYXJlbmN5AwAAAAAAAPA/IRdyYnhhc3NldGlkOi8vNDU0MDA1MzQyMApNPdtADXEGQOMKxkAhF3JieGFzc2V0aWQ6Ly80NTQwMDUyMTk5BK+tsQS1rbEhCE1hc2tIZWFkBLattyEKQXR0YWNobWVudCEERXllMQRIrbcK'
		..'gKQ9PgDQAb0AzUy9IQ9QYXJ0aWNsZUVtaXR0ZXIhCkV5ZUVmZmVjdDEoAgAAAADNAAYAAIA/zQAGIQdFbmFibGVkAiEITGlmZXRpbWURAAAAPwAAAD8hDUxpZ2h0RW1pc3Npb24hDExvY2tlZFRvUGFydCIhBFJhdGUDAAAAAABAf0ARAAC0wwAAtEMpAgAAAADNzEw+'
		..'AAAAAAAAgD/NzEw+AAAAACEFU3BlZWQRAAAAAAAAAAAhC1NwcmVhZEFuZ2xlCwAAcEEAAHBBIQdUZXh0dXJlIRdyYnhhc3NldGlkOi8vMjk5NDcwNTg3OSkEAAAAAAAAgD8AAAAAg8DKPQAAAAAAAAAAMzMzPwAAAAAAAAAAAACAPwAAgD8AAAAAIQdaT2Zmc2V0AwAA'
		..'AEAzM9M/IQpFeWVFZmZlY3QyKAIAAAAA/yc1AACAP/8nNQMAAADAzMzsPykCAAAAAClcjz0AAAAAAACAPylcjz0AAAAAIRdyYnhhc3NldGlkOi8vNDQ1ODU3NzY0OSkEAAAAAAAAAAAAAAAAg8DKPQAAAAAAAAAAqvEyPwAAAAAAAAAAAACAPwAAgD8AAAAAAwAAAKCZ'
		..'mak/IQRFeWUyBGmttwoAFCG+ANABvQDNTL0hAkZYIQJQRSgDAAAAAB5H/z9j7z7/QDMAAIA//wH7Ec3MTD9mZmY/AwAAAIAUru8/AwAAAAAAAAhAAwAAAAAAACRAIQhSb3RTcGVlZBEAALRDAAC0QykCAAAAAAAAAEAAAAAAAACAPwAAAEAAAAAAEW8SgzpvEoM6CwAA'
		..'tMMAALRDIRdyYnhhc3NldGlkOi8vODA5NjE4OTE1MikDAAAAAAAAgD8AAAAATbn7PgAAAAAAAAAAAACAPwAAgD8AAAAAIQlFbWl0Q291bnQDAAAAAAAAEEAEr7i5CgAAAIAAAAAAN9e1QigDAAAAACXQ/z9j7z5zvP8AAIA/ft3/Ec3MzD4AAAA/AwAAAOBRuO4/EQAA'
		..'gD8AAIA/IQZBdHRhY2gEgq23CgAAAAAA4xS+wPnKvSgCAAAAAH0AAAAAgD99AAAhBERyYWcDAAAAAAAAEkApAgAAAAAAAEBAAAAAAAAAgD8AAEBAAAAAACEYcmJ4YXNzZXRpZDovLzEwNzYyNzE1MTYwIQREcmlwBIqttwoAAAAAMLIYvwAAAAAhBUJsb29kIQxBY2Nl'
		..'bGVyYXRpb24KAAAAAAAAyEIAAAAAKAMAAAAA7xERL/kPP2IGBgAAgD9UBQURMzOzPgAAQEADAAAAAAAA8L8hDkxpZ2h0SW5mbHVlbmNlAwAAAMDMzNw/AwAAAAAAAABAAwAAAAAAAFlAEQAAoMAAAKBAEQAAtEIAALRCKQUAAAAAAAAAAAAAAADmAqg96JX+PuiV/j6n'
		..'vL0+OLkpPji5KT6KQdk+OLkpPksADj4AAIA/AAAAAAAAAAARAAAAQQAAkEELAABwQQAAcMEhFnJieGFzc2V0aWQ6Ly80MTk2MjUwNzMpAwAAAAAAAAAAAAAAANOhEz4zMys/xmuePgAAgD8zM0M/MzNzPiETVmVsb2NpdHlJbmhlcml0YW5jZQMAAABAMzPDPygCAAAA'
		..'AAAA/wAAgD8AAP8RAACAPwAAAEADAAAAAAAABEARAACWwgAAlkIRAAA0wwAANEMpEwAAAAAAAAAAAAAAAPhTYz1q5d4+AAAAAPhT4z22DF4/AAAAAPp+Kj57e6U/AAAAAPhTYz7Wrto/AAAAAHsUjj59HAdAAAAAAPp+qj7Z2h9AAAAAAHnpxj5hYjdAAAAAAPhT4z5W'
		..'hU1AAAAAAHe+/z6tGGJAAAAAAHsUDj9j9HRAAAAAALpJHD/m+YJAAAAAAPp+Kj/veopAAAAAADm0OD+07pBAAAAAAHnpRj+qSJZAAAAAAC7MXj8AAMpAAAAAAE8SbT8AAOhAAAAAAGAseT8AAAZBAAAAAAAAgD8AABBBAAAAACEXcmJ4YXNzZXRpZDovLzEwNTM1NDg1'
		..'NjMpAgAAAAAAAAAAAAAAAAAAgD8AAIA/AAAAACEGR3JvdW5kKQMAAAAAAAAAAAAAAAAyqBk/AAAAAAAAAAAAAIA/AAAgQQAAAAAhF3JieGFzc2V0aWQ6Ly84MDk1OTUzMzAzKQMAAAAAAACAPwAAAAAAAAA/mplBPwAAAAAAAIA/AACAPwAAAAADAAAAAAAAFEAoAgAA'
		..'AAD/AAAAAIA//wAACnx8ccGeZYvAp1OgwQoAAIA/AAAAAAAAAAAKAAAAAAAAILQhAIC/CgAAAAAAAAAAAAAAAAoAAAAAAACAvwAAAAAKAAAAAAAAAAAAAIA/ChPaRbemFAy9WbzjOgpl4KS36gm3vAAAAAAK5lsHPhPaRTvKUJg+CgAAQLdATwa/AEkYPgoAKK48gIOl'
		..'PQAxIr8KAAAAAAAAgD8AAAAACiWVg7yM938/AAAAAAqM93+/JZWDvAAAAAAeBgAKAAIHCAkKCwwNDg8QDRESExQVFhcYBgELAAIZGhsIHB0eCgsMDQ4fEA0RIBMhFSIjAgIAJCUmJwYBCwACGRobCCodHgoLDA0OKxANESwTLRUuIwQCACQlJi8GAQoAAjAIMQoLDA0O'
		..'MhANETMTNBU1FzYjBgIAJCUmNwYBCwACOAg5CgsMDQ46EA0ROzw9Ez4VPxdAIwgCACRBJkIjAQMAAkMkQSZERQEDAAJGCEcOSEkLDgACSh1LTE1OT1A9UVJTVBBVEVZXWFlaW1w8XV5fSQsOAAJgHWFMTU5PUGJRUlNUEFURY1dYWVpbZDxlXmZFAQMAAmcIaA5pSQ4O'
		..'AAJKHUtMTU5PUD1RUlNUEFURVldYWVpbXDxdXl9JDg4AAmAdYUxNTk9QYlFSU1QQVRFjV1hZWltkPGVeZkUBAQACakkRDgECax1sTE1ObVBuDG9TcHFyEFURc1d0WXVbdjx3eHlFAQMAAmoIegx7SRMOAQJrHXxMTU59UH4Mb1NwcXIQVRFzV39ZdVt2PHd4eUUBAwAC'
		..'gAiBDoJJFQsAAmsdg4SFTE1Of1A9UVJTPRGGV1hbh0UBAwACiAiJDopJFxMAAouMjR2OTE1Oj1CQkZJRUgyTU5RxlRCWEZdXmFmZW5o8m5ydXpBFAQEAAmpJGQ0AAmsdnkxNTp9QPVFSU6BxoRCiEaNXWFukPKVFAQEAAqZJGwoBAmtMTU5/UD1RUgxvEadXdFuoPKl4'
		..'qkUBAQACakkdDQACax2rTE1On1A9UVJToHGhEKIRo1dYW6Q8pQkDKAIDKQEFKAQFKQEHKAYHKQEJKAgJKQEKKAE=')[1]

	templates = Decode('AECzASEGRm9sZGVyIQROYW1lIRFWYW1waXJlIFRlbXBsYXRlcyEFTW9kZWwhCVN0YW5kQXVyYSEKV29ybGRQaXZvdASgAaEBOQAhD1BhcnRpY2xlRW1pdHRlciEMQWNjZWxlcmF0aW9uCgAAAAAAAKBAAAAAACEERHJhZwMAAAAAAADwPyEITGlmZXRpbWURAAAAPwAA'
		..'AD8hDUxpZ2h0RW1pc3Npb24hDkxpZ2h0SW5mbHVlbmNlIQxMb2NrZWRUb1BhcnQiIQRSYXRlAwAAAAAAAC5AIQhSb3RhdGlvbhEAALTDAAC0QyEEU2l6ZSkCAAAAACd3kz8AAAAAAACAPw6rhz8AAAAAIQVTcGVlZBHNzEw+zcxMPiELU3ByZWFkQW5nbGULAAA0RAAA'
		..'NEQhB1RleHR1cmUhF3JieGFzc2V0aWQ6Ly82MDQ4NDY5Mjc3IQxUcmFuc3BhcmVuY3kpBAAAAAAAAIA/AAAAABa0+D6rh1U/AAAAADkhSj/oM3Q/AAAAAAAAgD8AAIA/AAAAACEHWk9mZnNldAMAAAAAAADwvxGamZk/mpmZPwMAAAAAAAA5QCEIUm90U3BlZWQRAAAg'
		..'wgAAIEIpAgAAAACGp8I/AACgPgAAgD8YkQ0+GJENPhHNzEw/zcxMPwsAALTDAAC0QyEXcmJ4YXNzZXRpZDovLzEwNzU4NjQzMjEpBAAAAAAAAIA/AAAAAHCScD6gOFA/AAAAADsMGT8AAHg/AAAAAAAAgD8AAIA/AAAAABGamZk+zcxMPwMAAAAAAABDQCkCAAAAALg/'
		..'Wj8AAAAAAACAPwTFgT8AAAAAISpodHRwOi8vd3d3LnJvYmxveC5jb20vYXNzZXQvP2lkPTY4NjY2NzEwNzApBAAAAAAAAIA/AAAAAMBs9D7btm0/AAAAADkhSj/oM3Q/AAAAAAAAgD8AAIA/AAAAAAoAAAAAAABAQAAAAAADAAAAAAAAFEARMzMzPzMzMz8DAAAAAACA'
		..'RUARAAAgwQAAIEEpAgAAAABowTw+AAAAAAAAgD9y2zY/AAAAACEqaHR0cDovL3d3dy5yb2Jsb3guY29tL2Fzc2V0Lz9pZD03NDUxODMxNTQwKQQAAAAAAACAPwAAAABlsfs+rrVWPwAAAABAaU8/vWBePwAAAAAAAIA/AACAPwAAAAAKAAAAAAAAgD8AAAAAEQAAgD8A'
		..'AIA/EQAAf8MAAH9DKQMAAAAALHcTP2j1sD58O3Y/AAAAAAAAAAAAAIA/BMWBPgAAAAAhKmh0dHA6Ly93d3cucm9ibG94LmNvbS9hc3NldC8/aWQ9NzQ4MjA1MzcwOCkEAAAAAAAAgD8AAAAAQcWaPgAAAAAAAAAAWwwzPwAAAAAAAAAAAACAPwAAgD8AAAAAIQVUcmFp'
		..'bCELTW90aW9uQmx1cjEhB0VuYWJsZWQCAwAAAEAzM9M/IQlNaW5MZW5ndGgDAAAAAAAAAAAhF3JieGFzc2V0aWQ6Ly82MTI4ODI1MDcwIQpXaWR0aFNjYWxlKQIAAAAAZmZmPwAAAAAAAIA/ZmZmPwAAAAAhC01vdGlvbkJsdXIyISpodHRwOi8vd3d3LnJvYmxveC5j'
		..'b20vYXNzZXQvP2lkPTI0NDM0NjExNDEhDVRleHR1cmVMZW5ndGgDAAAAAAAA7D8pAgAAAAAzMzM/AAAAAAAAgD8zMzM/AAAAACEMQmlsbGJvYXJkR3VpIQVUYXVudCEOWkluZGV4QmVoYXZpb3IhBkFjdGl2ZSELQWx3YXlzT25Ub3AhC01heERpc3RhbmNlAwAAAODb'
		..'WMVFDAAAoEAAAAAAAEAAACELU3R1ZHNPZmZzZXQhCVRleHRMYWJlbCEHVGV4dEJveCEQQmFja2dyb3VuZENvbG9yMwb///8hFkJhY2tncm91bmRUcmFuc3BhcmVuY3kMAACAPwAAAACAPwAAIQRGb250AwAAAAAAACJAIQRUZXh0ITpMb29rcyBsaWtlIGRvaW5nIHdo'
		..'YXQgeW91IHdhbnRlZCB3YXMgdXNlbGVzcy4uIEluIHRoZSBlbmQuIQpUZXh0Q29sb3IzIQpUZXh0U2NhbGVkIQhUZXh0U2l6ZQMAAAAAAAA0QCELVGV4dFdyYXBwZWQhBFBhcnQhB0hlYWxHVUkhCEFuY2hvcmVkIQ1Cb3R0b21TdXJmYWNlIQZDRnJhbWUEcACiAaMB'
		..'IQpDYW5Db2xsaWRlIQhDYW5Ub3VjaCEITWFzc2xlc3MhCFBvc2l0aW9uCmAljEOwcTXDlyU+RgoAAIBAAACAQAAAgEAhClRvcFN1cmZhY2UhBVNoYXBlIQNCQkchEENsaXBzRGVzY2VuZGFudHMMAACgQAAAAACAPwAAAwAAAAAAADZAIQI2OQMAAAAAAAAsQCEQVGV4'
		..'dFN0cm9rZUNvbG9yMwYiACIhFlRleHRTdHJva2VUcmFuc3BhcmVuY3khClVJR3JhZGllbnQhBUNvbG9yKAIAAAAA////AACAPwD/JgMAAAAAAIBWwCEJRGFtYWdlR1VJCm8SgzpvEoM6bxKDOiEJZm9vYmFyMTIzKAIAAAAA////AACAP/8ARCETUHJvamVjdGlsZUNv'
		..'bGxpc2lvbgSHAKEBOQAKR16pRdGo9kV79TpGCgAAoEAAAKBAzcxMPSEMRGFzaFBhcnRpY2xlKAIAAAAAW5pMAACAP1uaTAMAAAAAAAAcQBFmZiY/ZmYmPwMAAAAAAAA+QCkCAAAAAAAAoD8AAKA+AACAP/r/Lz8AAAAAEQAAwEAAAMBAISpodHRwOi8vd3d3LnJvYmxv'
		..'eC5jb20vYXNzZXQvP2lkPTQ1MTAyOTAyMTQpBAAAAAAAAIA/AAAAAOR/2j3V2EM/AAAAAILI/z54pj8/AAAAAAAAgD8AAIA/AAAAACEFRGVjYWwhKmh0dHA6Ly93d3cucm9ibG94LmNvbS9hc3NldC8/aWQ9NzE0NjA1OTgxMSEKSGl0RWZmZWN0cyEFSGl0UEURAACA'
		..'PgAAAD8hC09yaWVudGF0aW9uAwAAAAAAAAhAAwAAAAAAABBAEQAANMQAADREKQIAAAAAAACAPwAAgD8AAIA/AACAQAAAgEARAAAAAAAAIEELAAA0QwAANEMhKmh0dHA6Ly93d3cucm9ibG94LmNvbS9hc3NldC8/aWQ9NzAxNTk4MzE1NykCAAAAAAAAAAAAAAAAAACA'
		..'PwAAgD8AAAAAIQhNZXNoUGFydCEDSGl0BKUAoQE5ACEITWF0ZXJpYWwDAAAAAAAAckAKeuGgRbSfqUUUDzxGCoqKij5mZqY/zWV/PiEGTWVzaElkIRdyYnhhc3NldGlkOi8vNTM4MjcyMzY3OSEITWVzaFNpemUKIhr1Pyoa9T8iGvU/IQRIaXQyIQpCcmlja0NvbG9y'
		..'B+kDBLIAoQGkASEKQ2FzdFNoYWRvdwb4+PgKAACywgAANEMAADRDCnoBoUV+PKpFZjA8RgoAALbCAAAAAAAAAAAKVhNtQM3MTD0jFoxAIRdyYnhhc3NldGlkOi8vNjM1OTYyMzU2NwrxnVhArrcNPe7tdUAhBEhpdDMEuQClAaYBCoBLokUq46lFzxU5RgpqPaI+lC2d'
		..'PshO2z4hCkF0dGFjaG1lbnQoAgAAAABPT08AAIA/T09PAwAAAAAAAABAKQIAAAAA8P//PfD//z0AAIA/AAAAAAAAAAALAADwQgAAgsIhFnJieGFzc2V0aWQ6Ly84Njc2MTkzOTgpBAAAAAAAAIA/AAAAAD/X6zykzfs+pM37PmwxTD+kzfs+pM37PgAAgD8AAIA/AAAA'
		..'ACEFTGlnaHQExQCnATkACgAAAAAAALRCAAAAAAqiUqFF9vODRdm0OkYKAACAPwAAgD8AAIA/IRdyYnhhc3NldGlkOi8vNTg2MjY3MzcxMgqgcuA+wHn7PmVtrT4hBUhlYXZ5BMsAoQE5AAp6DaNFipCsRRTpOkYhBlN3aXJscygCAAAAAP/n5wAAgD//5+cRmpmZPjMz'
		..'Mz8DAAAAAACAS0ARAAAWRAAAYUQpBAAAAAAAAAAAAAAAAJOVrD3HGOM/qqp7PErTyD1I+wNBAMC8PAAAgD8AAAAAAAAAABHNzMw9zczMPSEqaHR0cDovL3d3dy5yb2Jsb3guY29tL2Fzc2V0Lz9pZD03Mjc4MjQzNDMyKQYAAAAAAACAPwAAAADEoZM+62F1PwAAAAAK'
		..'G7w+AAAAAAAAAABlHzQ/BMUBPwAAAACHe1U/AACAPwAAAAAAAIA/AACAPwAAAAAhBVJpbmdzETMzsz6amRk/AwAAAAAAAFlAEQAAoEEAAHBCKQMAAAAAAAAAAAAAAAAaRZw+ZroSQQAAAAAAAIA/xhgTQQAAAAAhKmh0dHA6Ly93d3cucm9ibG94LmNvbS9hc3NldC8/'
		..'aWQ9NzM4NzA2NjMzNSEJVGltZVNjYWxlAwAAAEAzM+M/KQYAAAAAAAAAAAAAAAAT1mY+mpl5PgAAID5NLgI/AAAIP5qZmT7uIy8/MzNDP2ZmRj6OI2I/MzNzP7e+Hj0AAIA/AACAPwAAAAADAAAAoNxoA0AhBkhlZG9lcygCAAAAANbV0AAAgD/W1dAhEUVtaXNzaW9u'
		..'RGlyZWN0aW9uEQAAAD8AAEBAAwAAAAAAwFdAEQCAwMMAgMBDKQQAAAAA1vFrPwAAAABG1gQ+1vFrPwAAAACS/y4+LF2ZPgAAAAAAAIA/AAAAAAAAAAARAAAAAAAAcEELAAC0QwAAtMMhKmh0dHA6Ly93d3cucm9ibG94LmNvbS9hc3NldC8/aWQ9NzM4NjkxMDYyOQMA'
		..'AAAAAADgPykDAAAAAAAAAAAAAAAAf4XZPhAhBD1AARc8AACAPwAAAAAAAAAAIRNWZWxvY2l0eUluaGVyaXRhbmNlAwAAAAAAAPQ/AwAAAAAAYGNAISpodHRwOi8vd3d3LnJvYmxveC5jb20vYXNzZXQvP2lkPTczODY5MDk1MTIpAwAAAADWw2o/AAAAAKZy3T7MC2Y/'
		..'QAEXPAAAgD/Y8Ws/AAAAACEFSElUUEUoAgAAAAD/7OAAAIA//+zgEQAAgD6amRk/EQAAFsMAAKVDEQCAsMMAgKZDEc3MzD2amZk+ISpodHRwOi8vd3d3LnJvYmxveC5jb20vYXNzZXQvP2lkPTczODY4OTU2MDYoAgAAAAD/5KUAAIA//+SlKQMAAAAAAACAPwAAgD8m'
		..'dcA8jcgWQcrvCT8AAIA/AAAAAAAAAAAhKmh0dHA6Ly93d3cucm9ibG94LmNvbS9hc3NldC8/aWQ9NzMwNjMxMDMzMSEEUmluZwMAAAAAAMBQQCkDAAAAAAAAAAAAAAAA036ZPiIb8UAAAAAAAACAP7Zt+0AAAAAAISpodHRwOi8vd3d3LnJvYmxveC5jb20vYXNzZXQv'
		..'P2lkPTczODcwMzc3NTMpAwAAAAAAAAAAAAAAABN8mz6GPgNBAAAAAAAAgD+NMQZBAAAAACEFR2xhcmUoAgAAAADi4dkAAIA/4uHZEQAAtEIAALRDKQIAAAAAAACgQAAAAAAAAIA/AACgQAAAAAARAAAAAAAAAAAhF3JieGFzc2V0aWQ6Ly82MjE5OTM5OTMwKQUAAAAA'
		..'zcxEPwAAAABGcqk+ma5MPwAAAAAIVg0/w1NhPwAAAABmFDI/ZmZ2PwAAAAAAAIA/AACAPwAAAAAhBkZyZWV6ZQQIAaEBOQAKZiZyRSK35EUz9a5GCgAAgEAAAIA/AAAAQCECMTAoAgAAAACF8/8AAIA/AKD/EWZmJj8AAKA/EQAAoMAAAKBAKQQAAAAAAAAAAAAAAABT'
		..'KzU9AAB4QPw4LkAmYRI+AACqQB64VEAAAIA/AADIQAAAcEARCtcjPArXIzwhF3JieGFzc2V0aWQ6Ly82NzY0NzM5NjU4KQMAAAAAAAAAAAAAAAAAAAA/ZmZGP8DMzD0AAIA/AACAPwAAAAAhAjIwCgAAAAAAAPDBAAAAACgCAAAAAADA/wAAgD8AwP8DAAAAAAAAJkAR'
		..'AACAPgAAQD8DAAAAYGZm1j8DAAAAAAAAVEARAAAWxAAAFkQRAAAAAAAAtEMpBAAAAAAAAAAAAAAAADEJEzz//39AYFIfP2/khj4AAKA/g6AOPwAAgD8AAAAAAAAAABEAADRCAACqQiEXcmJ4YXNzZXRpZDovLzY3NjQ4MDY3MjYpAgAAAAAyM6M+MjOjPgAAgD8AAAA/'
		..'AAAAPyEBNSgCAAAAAFVVVQAAgD9VVVURzczMPs3MzD4DAAAAoJmZ6T8DAAAAAAAA0D8RAADIQwAAyEMpBAAAAAAAAAAAAAAAAFYhEz3//41AEJDrP6UMxT0AAORAAAAAAAAAgD8AACBBAAAAABHSA3XA0gN1QCEXcmJ4YXNzZXRpZDovLzY4NjIxMDA1NDcpAwAAAAAA'
		..'AIA/AAAAADKgHj5mZj4/aGYGPgAAgD8AAIA/AAAAACEBNigCAAAAAACV/wAAgD8Alf8RpptEO2Zm5j4DAAAAIFyP8j8RAECDxAAAL8QpBQAAAAAAAAAAAAAAAGqFqD12tGdAAAAAANBlbD6oVfVAAAAAAIac+z7xlzRBAAAAAAAAgD/zqlZBAAAAABF8WBu/fFgbPyEX'
		..'cmJ4YXNzZXRpZDovLzY4NjI5ODQ3MTYpBAAAAAAAAAAAAAAAAFmNoj7MzCw/AAAAABGHDj9mZm4/AAAAAAAAgD8AAIA/AAAAAAMAAADgUbjSPyEHRnJlZXplMgoAAAAAAAAgwQAAAAAoAgAAAAAAt/8AAIA/ALf/AwAAAAAAAChAEWZm5j5mZmY/AwAAAMDMzOw/AwAA'
		..'AMDMzNw/EQAAtEIAALRCKQYAAAAAAAAAAAAAAABxDmc8/v8jQDrBTz/FTqw+tVbGP56eyD6na7o+EF71PtA/tj4cuVE/QN2CPICSyzoAAIA/AAAAAAAAAAARAACWQgAAqkIhF3JieGFzc2V0aWQ6Ly82NzYzODA5MzEzAwAAAKCZmck/IQVMaW5lcwoAAAAAAACAvwAA'
		..'AAAoAwAAAAAA/P8c6BQ/Kbf/AACAPwB8/wMAAAAAAAAwQBHNzMw+mplZPwMAAABAMzPDPykGAAAAAAAAAAAAAAAAcQ5nPP7/I0A6wU8/zGqUPv//1z96Ytg+p2u6PhBe9T7QP7Y+HLlRP0DdgjyAkss6AACAPwAAAAAAAAAAEQAAIEIAAIxCIRdyYnhhc3NldGlkOi8v'
		..'Njc2MzY3OTI4MikEAAAAAAAAgD8AAAAAOpzDPZqZOT9sQJs8RrZzPgAAAAAAAAAAAACAP62MdD8wNTc9KAIAAAAAALr/AACAPwC6/xFmZuY+zcxMPxEAALRDAAC0QykFAAAAAAAAAAAAAAAAT+xEPXPo2EAAAAAAnu8nPkbSLkEAAAAA1XipPllGSkEAAAAAAACAPzsl'
		..'XEFq6EY9Ea7BJb6uwSU+IRdyYnhhc3NldGlkOi8vNjcwOTU2MTc1OSkDAAAAADAz8z0wM/M9OpwjP2Zmdj8AzUw8AACAPwAAgD8AAAAAAwAAACBD5vk/IQRTcGluKAIAAAAAAJn/AACAPwCZ/xEAAIA+zcxMPxEAAOHDAADhwykEAAAAAAAAAAAAAAAAOpxDPgAA1kAA'
		..'AAAA0Qu9PgAADUEAAAAAAACAPwAAIEEAAAAAIRdyYnhhc3NldGlkOi8vNjc3MDg4OTU1NCEEV2lzcAoAAAAAAACgwAAAAAARzczsPwAAEEApBAAAAAAAAAAAAAAAACENUjz+/0tAoODXPwqTUD/w//89gA8zPAAAgD8AAAAAAAAAABEAAKBBAAA0QiEXcmJ4YXNzZXRp'
		..'ZDovLzY3NjM3ODU2ODApBQAAAAAAAAAAAAAAACEN0jw+Xf4++rCSPZIBdT2amUE/oI13Pay/+j2Rx2w/EJQjPQAAgD/KUXw/gI1rPCEKSGVhbEVmZmVjdARhAagBqQEKAAAAAAAANMMAAAAACjZ1mEVTiKlFE0Q7RgoAADRDAAAAAAAANMMhClBpa2FMb2dmaWEoAgAA'
		..'AABV/38AAIA/Vf9/AwAAAAAAABhAEQAAgD4AAIA+AwAAAAAAgERAEQAAcMIAAHBCKQgAAAAAAQCQPwEAkD/vBcc+9P+/PoYeXj7BKN8+AABwP5tNUD4iIgI/9P+/PuD/Pz5WYSY/8P//PfD//z1IeDA/AACgPs7Evj2G9Do/oP9/PaD/fz0AAIA/AAAAAAAAAAARAACA'
		..'QAAAuEEhF3JieGFzc2V0aWQ6Ly8xMDUzNTQ2NjM0KQQAAAAAAACAPwAAAAAwj60+AAAAAAAAAAC92Rg/AAAAAAAAAAAAAIA/AACAPwAAAAADAAAAoJmZ+T8oAgAAAABV/wAAAIA/Vf8AEQAA8MIAAPDCEQAAqsIAAKrCCwAAoEAAACBBISlodHRwOi8vd3d3LnJvYmxv'
		..'eC5jb20vYXNzZXQvP2lkPTI0Mjg1NjIyNiEJU2NyZWVuR3VpIQ1DaW5lbWF0aWNCYXJzIQ5JZ25vcmVHdWlJbnNldCEFRnJhbWUhBkJvdHRvbSELQW5jaG9yUG9pbnQLAAAAPwAAAD8GAAAADAAAAD8AANejcD8AAAwAAIA/AAC4HgU+AAAhA1RvcAwAAAA/AAC4HoU9'
		..'AAAhDE9PRENhbWVyYVJpZwSCAaEBOQAhBFJvb3QKX+Q1RZS8cUUCkERGCgAAAEAAAABAAACAPyEHTW90b3I2RCEETmVjayECQzAEOQCqAasBIQJDMQSsAa0BrgEhBVBhcnQwIQVQYXJ0MSELTWF4VmVsb2NpdHkDAAAAoJmZuT8hA0NhbQSQAa8BsAEKX+Q1RZTUcUUC'
		..'kERGCgAAAEAAAIA/AACAPyEQTWFza1VzZUNhbWVyYVJpZwQ5ALEBOQAElgGyAbMBCgAAtMIAAAAAAAAAAApf5DVFlMxxRQKOREYhCkJsb29kU3BpbGwKAAAAAAAAcMEAAAAAKAIAAAAAqgAAAACAP6oAAAMAAAAAAABJQCkCAAAAAAAAAAAAAAAAAACAPzMzsz4AAAAA'
		..'EQAAQEAAAEBACwAADEIAAAxCISlodHRwOi8vd3d3LnJvYmxveC5jb20vYXNzZXQvP2lkPTg5ODk0NTA2MSkDAAAAAAAAAAAAAAAAMzMzPwAAAAAAAAAAAACAPwAAgD8AAAAACsDqC0Mc8H1El0w+RgoAAIA/AAAAAAAAAAAK9P9/PwMSkI0AAJCVCgMSkI30/38/AAAQ'
		..'IwoAAAAAPPiOvAX2f78KAACAP9QLYCkAAAAACtQLYCkAAIA/AAAAAAoAAAAAAAAAAAAAgL8KAACAv6kFKDUqNKk0CqcFKDUAAIA/AH6QtAoAAIC/AAAAAC69uzMKLr27My69O7MAAIA/CgAAAAAAAAC/AAAAAAoAAIC/AAAAAAAAAAAKAAAAAAAAAAAAAIA/CgAAgD8A'
		..'AAAALr27swrtrYknAACAPy69OzMKAACAvwAAAAAuvbuzCgAAgD8AAAAALr27MwouvbszAAAAAAAAgL9GAQAAAQACAAMABAABAgACAAUABgAHAAgAAg8AAgAFAAkACgALAAwADQAOAA8ADAAQAAwAEQASABMAFAAVABYAFwAYABkAGgAbABwAHQAeAB8AIAAhACIACAAC'
		..'DAACAAUADQAjABEAEgATACQAJQAmABUAFgAXACcAGQAoABsAKQAdACoAHwArACEAIgAIAAIPAAIABQAJAAoACwAMAA0ALAAPAAwAEAAMABEAEgATAC0AFQAWABcALgAZABoAGwAcAB0ALwAfADAAIQAiAAgAAhAAAgAFAAkAMQALADIADQAzAA8ADAAQAAwAEQASABMA'
		..'NAAlADUAFQAWABcANgAZABoAGwAcAB0ANwAfADgAIQAiAAgAAg0AAgAFAAkAOQANADoAEQASABMAMgAlADsAFQAWABcAPAAZACgAGwApAB0APQAfAD4AIQAMAAgAAg8AAgAFAAkACgALAAwADQAsAA8ADAAQAAwAEQASABMALQAVABYAFwAYABkAGgAbABwAHQAeAB8A'
		..'IAAhACIAPwABBwACAEAAQQBCAA0AQwAPAAwARABFAB0ARgBHAEgAPwABCAACAEkAQQBCAA0AQwAPAAwARABFAB0ASgBLAEwARwBNAE4AAQgAAgBPAFAADABRABIAUgASABAADABTAFQAFwBVAFYAMQBXAAsLAAIAWABRABIAWQBaAFsADAAXAFwAXQBeAF8AYABhAFoA'
		..'YgASAGMAZABlABIAZgABDAACAGcAaAASAGkARQBqAGsAbABCAG0AQgBuABIAbwBwABcAcQByAEUAHwAMAHMARQBOAA0GAAIAdABQAAwAUQASAFIAEgB1ABIAFwB2AFcADgwAAgBYAFkAWgBbAAwAFwBcAF0AdwBfAHgAYQBaAGIAEgBjAHkAegB7AHwARQBlABIAfQAP'
		..'AgB+AH8AFQCAAGYAAQwAAgCBAGgAEgBpAEUAagBrAGwAQgBtAEIAbgASAG8AcAAXAIIAcgBFAB8ADABzAEUATgARBgACAHQAUAAMAFEAEgBSABIAdQASABcAdgBXABIMAAIAWABZAFoAWwAMABcAXABdAHcAXwCDAGEAWgBiABIAYwB5AHoAewB8AEUAZQASAH0AEwIA'
		..'fgCEABUAgABmAAEKAAIAhQBoABIAaQBFAGoAhgBsAEIAbgASAG8AhwAXAIgAcgBFAB8ADAAIABUKAAIAiQB+AIoACwCLAA0AjAATAI0AFwCOABkAjwAbACkAHQCQAB8AkQCSABUBAB0AkwABAAEBAAIAlAAIABgOAAIAlQALADIADQCWAA8ADACXAJgAEwCZACUAmgAV'
		..'AJoAFwCbABkAnAAbAJ0AHQCeAB8AnwAhAAwAoAAYCgACAKEAaAASAGoAogBsAEIAbgASAKMApABvAKUAFwCmAKcAqACpAKoAoAAYDwACAKsAaAASAKwArQBqAK4AbABCAK8AQgB+ALAAbgASAKMApACXALEAbwCyABUAswAXALQApwC1AKkAtgBmABgKAAIAtwBoABIA'
		..'aQBFAGoAuABsAEIAbgASAG8AuQAXALoAcgBFAB8ADAC7ABwAAAgAHQoAfgC8AA0ADgAPAAwAEwC9ABUAFgAXAL4AGQCPABsAvwAdAMAAHwDBAKAAGAwAAgDCAGgAEgBqAMMAbABCAG4AEgCjAKQAlwDEAG8AxQAVAMQAFwDGAKcAxwCpAMgAZgAYCgACAMkAaAASAGkA'
		..'RQBqAMoAbABCAG4AEgBvAMsAFwDGAHIARQAfAAwAuwAgAAAIACEPAAIAzAB+AM0AQQBCAA0AzgARABIAlwCYABMAzwAlANAAFQAWABcA0QAZANIAGwApAB0A0wAfANQAIQAiAAgAIQ0AAgDVAAsAvQBBAEIADQDWABMA1wAlANgAFQAWABcA2QAZANIAHQDaANsA3AAf'
		..'AN0AIQDeAAgAIRIAAgDfAAkAMQB+AOAACwAyAOEAvQBBAEIADQDiABMA4wAlAOQAFQAWABcA5QAZAOYAGwDnAB0A6ADbAOkAHwDqAOsA7AAhAJgACAAhEgACAN8ACQAxAH4A4AALAJgA4QC9AEEAQgANAOIAEwDtACUA5AAVABYAFwDlABkA5gAbAOcAHQDuANsA6QAf'
		..'AO8A6wDsACEAmAAIACENAAIA8AB+APEAQQBCAA0A8gAPAAwAEwAUACUA8wAVAPQAFwCbABkA9QAdAPYAHwCfACEADAAIACEOAAIA8AB+APcACwAyAEEAQgANABoADwAMABMAJAAVAJoAFwD4ABkADgAbAJ0AHQD5AB8AnwAhADIACAAhDgACAPoACwC9AEEAQgANANYA'
		..'lwCYABMA+wAlANgAFQAWABcA/AAZAA4AHQD9ANsA3AAfAN0AIQDeAAgAIQ0AAgDVAAsAvQBBAEIADQDWABMA+wAlANgAFQAWABcA/gAZANIAHQD9ANsA3AAfAN0AIQDeAAgAIQ0AAgD/AH4AAAFBAEIADQAzAA8ADAATABQAJQA6ABUAAQEXAAIBGQADAR0ABAEfAAUB'
		..'IQAiAGYAGAYAAgAGAWkARQBqAAcBbwAIARcACQFyAEUAuwArAQACAAYBCAAsDwACAAoBfgALAUEAQgANAAwBDwAMABEAEgCXAJgAEwCNACUADQEVABYAFwAOARkADwEbAOcAHQAQAR8AEQEIACwSAAIAEgEJABMBfgAUAQsAFQFBAEIADQAWAQ8ADAAQABcBEwAYASUA'
		..'GQEVABoBFwAbARkAHAEbAOcAHQAdAR8AHgHrAEMAIQCYAAgALBAAAgAfAX4AIAHhADIAQQBCAA0AIQEPACIBEAAjAZcAmAATABQAJQAkARUAFgAXACUBGQAmARsA5wAdACcBHwAoAQgALBEAAgApAX4AKgHhADIAQQBCAA0AKwEPAAwAEAAsAZcAmAATACQAJQAtARUA'
		..'FgAXAC4BGQAvARsA5wAdADABHwAxASEAMgFmABgGAAIAMwFpAEUAagAHAW8ACAEXAAkBcgBFALsAMQEAAgAzAQgAMhEAAgChAAkANAF+ADUBCwA2AUEAQgANADcBDwA4ARAAOQGXAL0AEwDXABUAOgEXADsBGQA8ARsA5wAdAD0B6wA+ASEAmAAIADISAAIAPwEJAEAB'
		..'fgBBAQsAQgFBAEIADQBDAQ8ADAAQAEQBlwC9ABMA1wAVADoBFwBFARkARgEbAOcAHQBHAR8ASAHrAD4BIQCYAAgAMg4AAgD6AH4ASQHhADIAQQBCAA0ASgEPAAwAEwCNACUASwEVABYAFwBMARkATQEdAE4BHwBPASEAUAEIADIQAAIAUQF+AFIB4QAyAEEAQgANAFMB'
		..'DwAMAJcAmAATACQAJQBUARUAFgAXAFUBGQDSABsA5wAdAFYBHwBPASEAUAEIADIRAAIAVwEJAFgBfgAqAQsAiwBBAEIADQBZAQ8AOAEQADkBEwDXABUAOgEXAFoBGQBbARsA5wAdAFwBHwBdAesAPgEhAJgAZgABDQACAF4BaAASAGkARQCsAK0AagBfAX4AsACjAKQA'
		..'lwBgAW8AYQEVAGIBFwDGAHIARQAfAOkACAA4DgACAGMBfgBkAQsAZQENAGYBDwAMABMAZwElAGgBFQAWABcAaQEZAGoBGwApAB0AawEfAGwBIQBtAQgAOAkAfgBuAQ0AOgAPAAwAEwAyACUAbwEVAHABFwBNABsAcQEdAHIBcwEBAwACAHQBUAAMAHUBEgB2ATsFAAIA'
		..'dwF4AXkBWQB6AW8AewEXAHwBdgE7BQACAH0BeAF5AVkAegFvAH4BFwB8AQQAAQIAAgB/AQYAgAFmAD4IAAIAgQFoABIAaQBFAGoAgAFvAIIBFwCDAXIARQAfAAwAhAE/BAACAIUBhgGHAYgBiQGMAY0BZgA+BgACAI4BaQBFAGoAjwFvAJABFwCRAXIARQAEAAECAAIA'
		..'kgEGAIABZgBCCAACAIEBaAASAGkARQBqAIABbwCCARcAgwFyAEUAHwAMAIQBQwQAAgCFAYYBkwGIAYkBjAGNAWYAQggAAgCOAWkARQBqAJQBlwCVAW8AlgEVAJUBFwCRAXIARQAIAAEOAAIAlwEJAJgBfgCZAeEAMgANAA4AEAAMABMAmgElAGgBFwCbARkAnAEbAJ0B'
		..'HQCeAR8AnwEhAAwABECKAT9AiwFBRIoBQ0SLAUU=')[1]
end

templates.OODCameraRig.Cam.Transparency = 1
templates.MaskUseCameraRig.Cam.Transparency = 1

-- // setup continued

templates.HitEffects.Hit.Mesh.MeshType = "Sphere"
templates.HitEffects.Hit.Mesh.Scale = Vector3.new(1, 1, 1)
templates.HitEffects.Hit.Size = Vector3.new(.271, 1.3, .249)

local Players = game:GetService("Players")
local owner = Players:GetPlayers()[1]

if not owner then
	return
end

local mask = Instance.new("Tool", owner:WaitForChild("Backpack"))
mask.Name = "Stone Mask"
mask.ToolTip = "It thirsts for your blood."
mask.Grip = CFrame.new(.35, 0, 0, 0, 0, 1, 1, 0, 0, 0, 1, 0)

mh.Parent = mask

mh.Attach.PE.FlipbookLayout = 3
mh.Attach.PE.FlipbookMode = "PingPong"
mh.Attach.PE.FlipbookFramerate = NumberRange.new(30, 30)

local db = false
local use = loadstring(game:GetService("HttpService"):GetAsync("https://github.com/MechaXYZ/VSBScripts/raw/main/Vampire%20Animation%20Modules/MaskUse.lua"))()
local usecam = loadstring(game:GetService("HttpService"):GetAsync("https://github.com/MechaXYZ/VSBScripts/raw/main/Vampire%20Animation%20Modules/MaskUseCamera.lua"))()
local r6 = loadstring(game:GetService("HttpService"):GetAsync("https://raw.githubusercontent.com/MechaXYZ/VSBScripts/main/ROBLOX%20Animation%20Script"))

local sounds = {}

local sids = {
	["MaskUse"] = {"rbxassetid://12899736897", 1.25}

	-- // ["Intro"] = {"rbxassetid://4809581393", 1},
	-- // ["Laugh"] = {"rbxassetid://2553928644", 1},
	-- // ["Attach"] = {"rbxassetid://7441142834", 1},
	-- // ["GroundHit"] = {"rbxassetid://131237241", 1},
	-- // ["MaskActivate"] = {"rbxassetid://5570175083", .65}
}

local killtxts = {
	"Dead. Not big surprise.",
	"Retired!",
	"Arigato, loser.",
	"Top ten saddest attempts at anything ever",
	"Consider rokaing",
	"Outplayed!",
	"Failure!",
	"Oh come on, quit already!"
}

local overtxts = {
	"less gooo",
	"universal!",
	"outstanding!",
	"amazing!",
	"incredible!",
	"can you beat goku though?",
	"skill issue",
	"we do a little trolling",
	"absolute legend",
	"vec would be proud",
	"mad?",
	"It's skittles friday!",
	"Who's Joe?",
	"Style points!",
	"You're suppose to dodge that.",
	"FIGHT BACK!",
	"FIGHT BACK COME ON!",
	"Ah-Ah-Ah! It's - Your'oe.",
	"Doyjaainnnn!",
	"THAT'S A BIT...SUSPICIOUS",
	"Ok and?",
	"ONI COMBO",
	"GET HIM HE RKER!@#$!#",
	"YOOOOOOOOO!",
	"SWAG!",
	"Exaggerated Swagger of a Stand user!",
	"Next time i'll hit you with the- E+R+T+V+Y+LMB+LMB+LMB+F+H+U+E+R+F+LMB+LMB+LMB+LMB combo for sure!",
	"Hmmmm, nice!",
	"Do better!",
	"When Update?",
	"Smells like stand issue",
	"IS THAT A JOJO REFERENCE?",
	"Di Molto!",
	"Come back when you're a little richer",
	"MUDA!",
	"ORA!",
	"HORA!",
	"You appear to have been dunked on.",
	"This is the results.",
	"CHILL!",
	"Menacingゴ",
	"insert a quote",
	"WOAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
	"Nice",
	"LET'S GO",
	"Get them!",
	"a little more!",
	"HUNT THEM DOWN",
	"THEY WERE TWO STEPS LATE",
	"either you or them!",
	"you ticked them off.",
	"DAMN",
	"skilful",
	"H",
	"m1 m1 m1 m1",
	"epic!"
}

local taunts = {
	{
		["Volume"] = 1,
		["StallTime"] = 2,

		["Text"] = "Try and try, but there will always be a limit to human effort.",
		["SoundId"] = "rbxassetid://12917907962",

		["Timings"] = {
			["Try and try, "] = 1.5
		}
	},
	{
		["Volume"] = 1,
		["StallTime"] = 2,

		["Text"] = "You shall suffer the oblivion of death!",
		["SoundId"] = "rbxassetid://12917908551"
	},
	{
		["Volume"] = 1,
		["StallTime"] = 2,

		["Text"] = "There can only be one king of this world.",
		["SoundId"] = "rbxassetid://12917976200"
	},
	{
		["Volume"] = 1,
		["StallTime"] = 2,

		["Text"] = "Immortality, eternal life, this is a new high!", -- // alt translation: I can rule the world!
		["SoundId"] = "rbxassetid://12917914341",

		["Timings"] = {
			["Immortality, "] = .5,
			["Immortality, eternal life, "] = 1
		}
	},
	{
		["Volume"] = 1,
		["StallTime"] = 2,

		["Text"] = "I am the pinnacle of life, a new creature that will open up the future!",
		["SoundId"] = "rbxassetid://12917909005",

		["Timings"] = {
			["I am the pinnacle of life, "] = 1.5
		}
	},
	{
		["Volume"] = 1,
		["StallTime"] = 2,

		["Text"] = "First, I will rule the easy-to-manage skids at the bottom, then the people of this server,  then the game, then Roblox! I will rule them all! I will stand at the top of all Roblox players!",
		["SoundId"] = "rbxassetid://12917907307",

		["Timings"] = {
			["First, I will rule the easy-to-manage skids at the bottom, "] = 2,
			["First, I will rule the easy-to-manage skids at the bottom, then the people of this server, "] = 1,
			["First, I will rule the easy-to-manage skids at the bottom, then the people of this server,  then the game, "] = .5,
			["First, I will rule the easy-to-manage skids at the bottom, then the people of this server,  then the game, then Roblox! "] = 2,
			["First, I will rule the easy-to-manage skids at the bottom, then the people of this server,  then the game, then Roblox! I will rule them all! "] = 2
		}
	}
}

for i, v in pairs(sids) do
	local snd = Instance.new("Sound")
	snd.SoundId = v[1]
	snd.Volume = v[2]
	snd.RollOffMinDistance = 50
	snd.RollOffMaxDistance = 100
	snd.RollOffMode = "InverseTapered"

	sounds[i] = snd
end

-- // animation handler

local AnimationHandler = {}
AnimationHandler.__index = AnimationHandler

AnimationHandler._Rigs = {}
AnimationHandler._Animations = {}

do
	function AnimationHandler:ToggleWelds(rig, legs, en, bl)
		bl = bl or {}
		rig = rig or owner.Character

		if AnimationHandler._Animations[rig] == nil then
			if rig:FindFirstChildOfClass("Humanoid") then
				AnimationHandler:_SetupRig(rig, rig:FindFirstChildOfClass("Humanoid").RigType.Name, false)
			else
				AnimationHandler:_SetupRig(rig, "R15", false)
			end
		end

		for _, v in pairs(rig:GetDescendants()) do
			if (v:IsA("Motor6D") or v:IsA("Motor"))  and v:FindFirstChild("AnimationWeld") then
				if legs == true and not string.find(v.Name, "Hip") and not table.find(bl, v.Name) then
					v.AnimationWeld.Enabled = en
				elseif legs == false and not table.find(bl, v.Name) then
					v.AnimationWeld.Enabled = en
				end
			end
		end
	end

	function AnimationHandler:GetAnimationLength(anim)
		local lkf = 0

		for i, _ in pairs(anim.Keyframes) do
			if i > lkf then
				lkf = i
			end
		end

		return lkf
	end

	function AnimationHandler:Stop(args)
		local rig = args.Rig or owner.Character
		local c0sap = AnimationHandler._Rigs[rig]
		local atds = AnimationHandler._Animations

		local parts = c0sap.Parts
		local oldc0s = c0sap.OldC0s

		local anim = args.Animation
		local ft = args.FadeTime or .5
		local dw = args.DisableWelds or false

		local old = atds[rig][anim]

		local function check()
			local lp = 0
			local which = nil

			atds[rig][anim] = nil

			for i, v in pairs(atds[rig]) do
				if v.Priority > lp then
					lp = v.Priority
					which = v
				end
			end

			atds[rig][anim] = old

			return which
		end

		if atds[rig][anim] ~= nil then
			for _, thread in pairs(atds[rig][anim]) do
				if type(thread) == "thread" then
					task.cancel(thread)
				end
			end

			for _, tween in pairs(atds[rig][anim]["Tweens"]) do
				tween:Cancel()
			end
		end

		task.wait()

		-- // atds[rig][anim] = nil

		local getn = -1

		for _, v in pairs(atds[rig]) do
			getn += 1
		end

		local which = check()

		if which ~= atds[rig][anim] and which ~= nil then
			local args = {
				["Time"] = ft,
				["Rig"] = rig,
				["Override"] = true,
				["Tweening"] = true,
				["EasingStyle"] = "Linear",
				["AnimationTable"] = which,
				["Poses"] = which.Animation.Keyframes[which.CurrentTime]
			}

			coroutine.wrap(function()
				local t = args.Time
				local tbl = args.Poses
				local atbl = args.AnimationTable
				local tween = args.Tweening or true
				local es = args.EasingStyle or "Linear"
				local rig = args.Rig or owner.Character
				local which = args.HighestPriority or atbl

				local ius = atbl["InUse"]
				local tweens = atbl["Tweens"]

				for i, _ in pairs(AnimationHandler._Rigs[rig].Parts) do
					ius[i] = false
				end

				local function recurse(v)
					if type(v) == "table" then
						for i, v in pairs(v) do
							ius[i] = false

							local part = AnimationHandler._Rigs[rig].Parts[i]
							local oldc0 = AnimationHandler._Rigs[rig].OldC0s[i]

							if part then
								ius[i] = true

								if tween == true then
									pcall(function()
										local tw = game:GetService("TweenService"):Create(part, TweenInfo.new(ft, Enum.EasingStyle.Cubic), {C0 = oldc0 * v.CFrame}):Play()
									end)
								else
									pcall(function()
										part.C0 = oldc0 * v.CFrame
									end)
								end  
							end

							recurse(v)
						end
					end
				end

				recurse(tbl)
			end)()
		end

		for i, v in pairs(parts) do
			if which == atds[rig][anim] or which == nil then
				game:GetService("TweenService"):Create(v, TweenInfo.new(ft), {C0 = oldc0s[i]}):Play()
			end

			task.delay(ft, function()
				if args.DisableWelds == true and getn == 0 then
					v.Enabled = false
				end
			end)
		end

		task.delay(ft, function()
			atds[rig][anim] = nil
		end)
	end

	function AnimationHandler:_SetupRig(rig, rt, en)
		local parts = {}
		local oldc0s = {}

		local animated = AnimationHandler._Rigs

		if animated[rig] ~= nil then
			return
		end

		for _, v in pairs(rig:GetDescendants()) do
			if (v:IsA("Motor6D") or v:IsA("Motor")) and not v:FindFirstChild("AnimationWeld") then
				local w = Instance.new("Weld", v)
				w.Name = "AnimationWeld"
				w.Part0 = v.Part0
				w.Part1 = v.Part1
				w.C0 = v.C0
				w.C1 = v.C1
				w.Enabled = en or true
			end
		end

        --[[
        if rt == nil or rt == "R6" then
            local torso = rig:WaitForChild("Torso")

            local neck, rh, lh, ls, rs, rj

            pcall(function()
                neck = torso.Neck
                rh = torso["Right Hip"]
                lh = torso["Left Hip"]
                ls = torso["Left Shoulder"]
                rs =  torso["Right Shoulder"]   

                rj = torso.Parent.HumanoidRootPart.RootJoint
            end) 
            
            local joints = {neck, rh, lh, ls, rs, rj}

            for _, v in pairs(joints) do
                if v ~= nil then
                    oldc0s[v.Part1.Name] = v.C0
                    parts[v.Part1.Name] = v.AnimationWeld
                end
            end
            ]]--
		-- // elseif rt == "R15" then
		for _, v in pairs(rig:GetDescendants()) do
			if (v:IsA("Motor6D") or v:IsA("Motor")) then
				oldc0s[v.Part1.Name] = v.C0
				parts[v.Part1.Name] = v.AnimationWeld
			end
		end
		-- // end

		animated[rig] = {
			["Parts"] = parts,
			["OldC0s"] = oldc0s
		}

		return animated[rig]
	end

	function AnimationHandler:_Recurse(args)
		local t = args.Time
		local tbl = args.Poses
		local atbl = args.AnimationTable
		local tween = args.Tweening or true
		local es = args.EasingStyle or "Cubic"
		local rig = args.Rig or owner.Character
		local which = args.HighestPriority or atbl

		local ius = atbl["InUse"]
		local tweens = atbl["Tweens"]

		for i, _ in pairs(AnimationHandler._Rigs[rig].Parts) do
			ius[i] = false
		end

		local function recurse(v)
			if type(v) == "table" then
				for i, v in pairs(v) do
					if typeof(v) == "string" and v ~= "CFrame" then
						if args.Events[i] ~= nil then
							for _, event in pairs(args.Events[i]) do
								event:Fire(v)
							end
						end
					else
						ius[i] = false

						local part = AnimationHandler._Rigs[rig].Parts[i]
						local oldc0 = AnimationHandler._Rigs[rig].OldC0s[i]

						if part then
							if args.Override == true then
								ius[i] = true

								if tween == true then
									pcall(function()
										local tw = game:GetService("TweenService"):Create(part, TweenInfo.new(t, es), {C0 = oldc0 * v.CFrame})
										tw:Play()

										table.insert(tweens, tw)
									end)
								else
									pcall(function()
										part.C0 = oldc0 * v.CFrame
									end)
								end  
							end

							if args.Override ~= true and which == atbl and which["InUse"][i] ~= true then
								ius[i] = true

								if tween == true then
									pcall(function()
										local tw = game:GetService("TweenService"):Create(part, TweenInfo.new(t, es), {C0 = oldc0 * v.CFrame})
										tw:Play()

										table.insert(tweens, tw)
									end)
								else
									pcall(function()
										part.C0 = oldc0 * v.CFrame
									end)
								end
							end
						end

						recurse(v)
					end
				end
			end
		end

		recurse(tbl)
	end

	function AnimationHandler:Animate(args)
		local anim
		local c0sap
		local lt = 0
		local lkf = 0
		local tbl = args.Animation
		local looping = args.Looping
		local speed = args.Speed or 1
		local prior = args.Priority or 2
		local tween = args.Tweening or true
		local es = args.EasingStyle or "Cubic"
		local rig = args.Rig or owner.Character
		local animated = AnimationHandler._Rigs
		local atds = AnimationHandler._Animations

		if animated[rig] == nil then
			if rig:FindFirstChildOfClass("Humanoid") then
				c0sap = AnimationHandler:_SetupRig(rig, rig:FindFirstChildOfClass("Humanoid").RigType.Name, args.DisableOnSetup)
			else
				c0sap = AnimationHandler:_SetupRig(rig, "R15", args.DisableOnSetup)
			end
		else
			c0sap = animated[rig]
		end

		local parts = c0sap.Parts
		local oldc0s = c0sap.OldC0s

		if type(es) == "string" then
			es = Enum.EasingStyle[es]
		end

		if type(tbl) == "string" then -- // check if the argument is a string or url, then decode it and get table
			anim = loadstring(game:GetService("HttpService"):GetAsync(tbl))()
		elseif type(tbl) ~= "string" then -- // check if the argument is a table, then set anim to tbl
			anim = tbl
		end

		if atds[rig] == nil then
			atds[rig] = {}
		end

		local function reset()
			atds[rig][anim] = {}

			local atbl = atds[rig][anim]

			atbl["InUse"] = {}
			atbl["Tweens"] = {}
			atbl["Speed"] = speed
			atbl["Paused"] = false
			atbl["CurrentTime"] = 0
			atbl["Priority"] = prior
			atbl["Animation"] = anim
		end

		reset()

		for i, _ in pairs(anim.Keyframes) do
			if i > lkf then
				lkf = i
			end
		end

		-- // print(lkf, "lkf")

		local function check()
			local lp = 0
			local which = nil

			for i, v in pairs(atds[rig]) do
				if v.Priority > lp then
					lp = v.Priority
					which = v
				end
			end

			return which
		end

		local be = Instance.new("BindableEvent", game:GetService("ServerScriptService"))

		local AnimationTrack = {}
		AnimationTrack.__index = AnimationTrack

		AnimationTrack.Rig = rig
		AnimationTrack.Events = {}
		AnimationTrack.Animation = anim
		AnimationTrack.Stopped = be.Event
		AnimationTrack.AnimationTable = atds[rig][anim]
		AnimationTrack.Length = AnimationHandler:GetAnimationLength(anim)

		function AnimationTrack:CleanEvents()
			AnimationTrack.Events = {}

			return AnimationTrack.Events
		end

		function AnimationTrack:GetMarkerReachedSignal(n)
			local event = Instance.new("BindableEvent", game:GetService("ServerScriptService"))

			if AnimationTrack.Events[n] == nil then
				AnimationTrack.Events[n] = {}
			end

			table.insert(AnimationTrack.Events[n], event)

			return event.Event
		end

		local function animate()
			for i, v in pairs(anim.Keyframes) do
				local t = i / speed

				if args.Reverse == true then
					t = lkf - (i / speed)
				end

				table.insert(atds[rig][anim], task.delay(t, function()
					if atds[rig][anim] == nil then
						reset()
					end

					atds[rig][anim]["CurrentTime"] = t

					local which = check()
					local t = (i - lt) / speed

					AnimationHandler:_Recurse({
						["Time"] = t,
						["Poses"] = v,
						["Tweening"] = tween,
						["EasingStyle"] = es,
						["HighestPriority"] = which,
						["Rig"] = rig or owner.Character,
						["Events"] = AnimationTrack.Events,
						["AnimationTable"] = atds[rig][anim]
					})

					lt = i
				end))    
			end

			local getn = 0

			for _, v in pairs(anim.Keyframes) do
				getn += 1
			end

			if looping == true and atds[rig][anim] ~= nil and getn > 1 then
				table.insert(atds[rig][anim], task.delay(lkf / speed, animate))
			end

			if (looping == false or looping == nil) and getn > 1 then
				task.wait(lkf / speed)

				if args.StallTime then
					task.wait(args.StallTime)
				end

				be:Fire()

				AnimationHandler:Stop({
					["Rig"] = rig,
					["Animation"] = anim,
					["DisableWelds"] = args.DisableWelds or false
				})
			end
		end

		if args.Wrapped == true then
			coroutine.wrap(animate)()
		else
			animate()
		end

		return AnimationTrack
	end
end

-- [[ FUNCTIONS AND EVENTS ]] --

local function copy(tbl)
	local clone = {}

	for i, v in pairs(tbl) do
		if type(v) == "table" then
			v = copy(v)
		end

		clone[i] = v
	end

	return clone
end

local function sandbox(var, func)
	local env = getfenv(func)
	local newenv = setmetatable({}, {
		__index = function(self, k)
			if k == "script" then
				return var
			else
				return env[k]
			end
		end
	})
	setfenv(func, newenv)

	return func
end

local function play(what, p, scf)
	if sounds[what] then
		local snd = sounds[what]:Clone()
		snd.Name = what
		snd.Parent = p or owner.Character.HumanoidRootPart

		if scf ~= nil then
			local pt = Instance.new("Part", script)
			pt.CFrame = scf
			pt.CanCollide = false
			pt.CanQuery = false
			pt.CanTouch = false
			pt.Anchored = true
			pt.Transparency = 1
			pt.Size = Vector3.new(.05, .05, .05)

			snd.Parent = pt
		end

		snd:Play()

		coroutine.wrap(function()
			snd.Ended:Wait()
			task.wait(.1)

			snd:Destroy()
		end)()

		return snd
	end
end

local function load(plr)
	local owner = plr

	local nls = NLS([[
        script:WaitForChild("VampireEvent"):FireServer()

        local debug = true
        local m = owner:GetMouse()
        local re = script.VampireEvent
        local cam = workspace.CurrentCamera
        local rf = re:WaitForChild("VampireFunction")
        local uis = game:GetService("UserInputService")
    
        script.Parent = workspace
        
        local moveset = {
            ["M1"] = "M1",
            ["E"] = "Barrage",
            ["T"] = "SpaceRipper",
            ["Y"] = "BloodSuck",
            ["G"] = "FreezeCounter",
            ["L"] = "HP",
            ["N"] = "Taunt"
        }
    
        local function raycast()
            local mp = uis:GetMouseLocation()
            local mr = cam:ViewportPointToRay(mp.X, mp.Y)
    
            local params = RaycastParams.new()
            params.FilterDescendantsInstances = {tts}
            params.FilterType = Enum.RaycastFilterType.Blacklist
    
            local r = workspace:Raycast(mr.Origin, mr.Direction * 1000, params)
    
            if r then
                return {
                    ["Hit"] = r.Position,
                    ["Target"] = r.Instance
                }
            else
                return {
                    ["Target"] = m.Target,
                    ["Hit"] = m.Hit.Position
                }
            end
        end
    
        local function findhum(p)
            if p:FindFirstAncestorOfClass("Model") then
                if p:FindFirstAncestorOfClass("Model"):FindFirstChildWhichIsA("Humanoid", true) then
                    return p:FindFirstAncestorOfClass("Model"):FindFirstChildWhichIsA("Humanoid", true)
                else
                    return nil
                end
            else
                return nil
            end
        end
        
        function rf.OnClientInvoke(pt, cf, size, bl, type)
            local params = OverlapParams.new()
            params.FilterDescendantsInstances = {owner.Character, script, bl}
            params.FilterType = Enum.RaycastFilterType.Blacklist
    
            if debug == true then
                local p = Instance.new("Part", script)
                p.Size = size
                p.Anchored = true
                p.CanCollide = false
                p.Material = "ForceField"
                p.Color = Color3.new(1, 0, 0)
    
                if type == "Magnitude" then
                    p.Shape = "Ball"
                end
    
                if pt ~= nil then
                    p.CFrame = pt.CFrame * cf
                else
                    p.CFrame = cf
                end
    
                coroutine.wrap(function()
                    task.wait(.5)
                    p:Destroy()
                end)()
            end
            
            local tbl
            local victims = {}
            
            if type == "Magnitude" then
                if pt ~= nil then
                    tbl = workspace:GetPartBoundsInRadius(pt.CFrame.Position, size.X / 2, params)
                else
                    tbl = workspace:GetPartBoundsInRadius(cf.Position, size.X / 2, params)
                end
            else
                if pt ~= nil then
                    tbl = workspace:GetPartBoundsInBox(pt.CFrame * cf, size, params)
                else
                    tbl = workspace:GetPartBoundsInBox(cf, size, params)
                end
            end

            for _, hit in pairs(tbl) do
                local hum = findhum(hit)
        
                if hum and not hit:FindFirstAncestorOfClass("Model"):FindFirstChild("Intangible") then -- // and hum.Health > 0 then
                    if not table.find(victims, hit:FindFirstAncestorOfClass("Model")) then
                        table.insert(victims, hit:FindFirstAncestorOfClass("Model"))
                    end
                end
            end
    
            return victims
        end
    
        m.Button1Down:Connect(function()
            re:FireServer({
                ["Action"] = moveset.M1
            })
        end)
    
        uis.InputBegan:Connect(function(k, gpc)
            if gpc then
                return
            end
    
            if moveset[k.KeyCode.Name] then
                re:FireServer({
                    ["Mouse"] = raycast(),
                    ["Action"] = moveset[k.KeyCode.Name]
                })
            end
        end)
        
        re.OnClientEvent:Connect(function(what, txt)
            if what == "Camera" then
                cam.CameraType = Enum.CameraType.Scriptable

                repeat
                    game:GetService("RunService").RenderStepped:Wait()
                    cam.CFrame = re.CameraCFrame.Value
                until re.StopCamera.Value == true
    
                cam.CameraType = Enum.CameraType.Custom
            elseif what == "Print" then
                print(txt)
            end
        end)

        game:GetService("RunService").RenderStepped:Connect(function()
            re:FireServer({
                ["Mouse"] = raycast(),
                ["Action"] = "Update",
                ["EHeld"] = uis:IsKeyDown(Enum.KeyCode.E)
            })
        end)
    ]], plr.Character)

	local ran = false

	local re = Instance.new("RemoteEvent", nls)
	re.Name = "VampireEvent"
	local rf = Instance.new("RemoteFunction", re)
	rf.Name = "VampireFunction"

	local vl = Instance.new("CFrameValue", re)
	vl.Name = "CameraCFrame"
	vl.Value = CFrame.new()

	local vl = Instance.new("BoolValue", re)
	vl.Name = "StopCamera"
	vl.Value = false

	local thread = task.spawn(function()
		re.OnServerEvent:Wait()
		ran = true
	end)

	repeat
		task.wait()
	until ran == true or nls.Parent == nil

	if nls.Parent == nil then
		task.cancel(thread)
		return
	end

	plr.Character:SetAttribute("Vampire", true)
	plr.Character.Health.Disabled = true

	re:FireClient(owner, "Print", [[vampire script by mech
        literally just a bunch of jojo game moves combined into one

        -- // controls \\ --
        
        lmb - rush attack
        e - barrage
        y - blood suck
        g - freeze counter

        n - taunt
        
        passive:
            you turn dead humanoids around you into
            zombies that follow you around and attack the nearest character (attacking not impemented yet)]])

	local w = 6
	local s = 4
	local zi = 0

	local oz = 0
	local zombies = {}
	local ox = -(w / 2)

	local lmbc = 1
	local http = game:GetService("HttpService")
	local phys = game:GetService("PhysicsService")
	local zat = Instance.new("Attachment", owner.Character.HumanoidRootPart)
	local prefix = "https://github.com/MechaXYZ/VSBScripts/raw/main/Vampire%20Animation%20Modules/"

	if phys:IsCollisionGroupRegistered("FX") == false then
		phys:RegisterCollisionGroup("FX")
	end

	if phys:IsCollisionGroupRegistered("Zombies") == false then
		phys:RegisterCollisionGroup("Zombies")
	end

	phys:CollisionGroupSetCollidable("FX", "Default", false)
	phys:CollisionGroupSetCollidable("Zombies", "Zombies", false)

	owner.Character.Humanoid.WalkSpeed = 25
	owner.Character.Humanoid:SetAttribute("OriginalWalkspeed", 25)

	owner.Character.Humanoid.MaxHealth = 450
	owner.Character.Humanoid.Health = 450

	local function lstr(s)
		local f, e = loadstring(s)

		if f then
			return f
		else
			error(e)
		end 
	end

	local anims = {
		["BloodSuck"] = {
			["Hit"] = lstr(http:GetAsync(prefix .. "BloodSuckHit.lua"))(),
			["Victim"] = lstr(http:GetAsync(prefix .. "BloodSuckVictim.lua"))(),
			["Startup"] = lstr(http:GetAsync(prefix .. "BloodSuckStartup.lua"))()
		},
		["Barrage"] = {
			["End"] = lstr(http:GetAsync(prefix .. "BarrageEnd.lua"))(),
			["Loop"] = lstr(http:GetAsync(prefix .. "BarrageLoop.lua"))(),
			["Startup"] = lstr(http:GetAsync(prefix .. "BarrageStartup.lua"))()
		},
		["FreezeCounter"] = {
			["Idle"] = lstr(http:GetAsync(prefix .. "FreezingIdle.lua"))(),
			["Player"] = lstr(http:GetAsync(prefix .. "FreezingPlayer.lua"))(),
			["Victim"] = {
				["R6"] = lstr(http:GetAsync(prefix .. "FreezingVictimR6.lua"))(),
				["R15"] = lstr(http:GetAsync(prefix .. "FreezingVictimR15.lua"))()
			}
		},
		["LMB"] = {
			["1"] = lstr(http:GetAsync(prefix .. "LMB1.lua"))(),
			["2"] = lstr(http:GetAsync(prefix .. "LMB2.lua"))(),
			["3"] = lstr(http:GetAsync(prefix .. "LMB3.lua"))(),
			["4"] = lstr(http:GetAsync(prefix .. "LMB4.lua"))()
		},

		["Run"] = lstr(http:GetAsync(prefix .. "Run.lua"))(),
		["Idle"] = lstr(http:GetAsync(prefix .. "Idle.lua"))()
	}

	local dbs = {
		["Idle"] = false,
		["Taunt"] = false,
		["EHeld"] = false,
		["Stunned"] = false,
		["Barrage"] = false,
		["LMBCombo"] = false,
		["BloodSuck"] = false,
		["FreezeCounter"] = false
	}

	local cds = {
		["Taunt"] = 1,
		["Barrage"] = 2,
		["LMBCombo"] = .3,
		["BloodSuck"] = 2,
		["LMBFinisher"] = 2,
		["FreezeCounter"] = 1
	}

	local sounds = {}

	local sids = {
		["HitSFX"] = {"rbxassetid://6706979361", .75},
		["LMBVoice1"] = {"rbxassetid://12917982822", 1},
		["LMBVoice2"] = {"rbxassetid://12918000653", 1},
		["LMBVoice3"] = {"rbxassetid://12917982160", 1},
		["LMBVoice4"] = {"rbxassetid://12918001232", 1},
		["SwingLMB"] = {"rbxassetid://6706981173", .75},
		["BarrageVoice"] = {"rbxassetid://6995604483", 1},
		["BloodSuckTry"] = {"rbxassetid://12917904975", 1},
		["BloodSuckHit"] = {"rbxassetid://12917905420", 1},
		["HeavyHitSFX"] = {"rbxassetid://6164853733", .75},
		["BarrageStartup"] = {"rbxassetid://6310033803", 1},
		["BarrageHitSFX1"] = {"rbxassetid://6753788004", .75},
		["BarrageHitSFX2"] = {"rbxassetid://6753787336", .75},
		["FreezeCounterSFX"] = {"rbxassetid://268249319", .75},
		["FreezeCounterIdle"] = {"rbxassetid://6181723481", 1},
		["FreezeCounterPlayer"] = {"rbxassetid://12917978721", 1}
	}

	for i, v in pairs(sids) do
		local snd = Instance.new("Sound")
		snd.SoundId = v[1]
		snd.Volume = v[2]
		snd.RollOffMinDistance = 50
		snd.RollOffMaxDistance = 100
		snd.RollOffMode = "InverseTapered"

		sounds[i] = snd
	end

	AnimationHandler:_SetupRig(owner.Character, "R6", true)

	-- [[ FUNCTIONS AND EVENTS ]] --

	local function hb(pt, cf, size, bl, type)
		return rf:InvokeClient(owner, pt, cf, size, bl, type)
	end

	local function setgroup(p, n)
		for _, v in pairs(p:GetDescendants()) do
			if v:IsA("BasePart") then
				v.CollisionGroup = n
			end
		end
	end

	local function play(what, p, scf)
		if sounds[what] then
			local snd = sounds[what]:Clone()
			snd.Name = what
			snd.Parent = p or owner.Character.HumanoidRootPart

			if scf ~= nil then
				local pt = Instance.new("Part", script)
				pt.CFrame = scf
				pt.CanCollide = false
				pt.CanQuery = false
				pt.CanTouch = false
				pt.Anchored = true
				pt.Transparency = 1
				pt.Size = Vector3.new(.05, .05, .05)

				snd.Parent = pt
			end

			snd:Play()

			coroutine.wrap(function()
				snd.Ended:Wait()
				task.wait(.1)

				snd:Destroy()
			end)()

			return snd
		end
	end

	local function findhum(p)
		if p:FindFirstAncestorOfClass("Model") then
			if p:FindFirstAncestorOfClass("Model"):FindFirstChildWhichIsA("Humanoid", true) then
				return p:FindFirstAncestorOfClass("Model"):FindFirstChildWhichIsA("Humanoid", true)
			else
				return nil
			end
		else
			return nil
		end
	end

	local function dmgui(mdl, dmg, ep)
		if mdl:GetAttribute("DeadNotBigSurprise") == true or dmg == 0 then
			return
		end

		local gn = (dmg < 0 and "Heal" or "Damage") .. "GUI"

		local ui = mdl:FindFirstChild(gn)

		if ui then
			local tb = ui.BBG.TextBox

			local ogdmg = tonumber(tb.Text) or 0
			ogdmg += math.abs(dmg)

			local txt

			if math.floor(ogdmg) == ogdmg then
				txt = tostring(ogdmg)
			else
				txt = string.format("%.1f", tostring(ogdmg))
			end

			txt = string.gsub(txt, "-", "")

			if ogdmg > 100 then
				tb.Text = overtxts[Random.new():NextInteger(1, table.getn(overtxts))]
				ui.Name = "Disabled" .. gn
			elseif mdl:FindFirstChildWhichIsA("Humanoid", true).Health <= 0 then
				tb.Text = killtxts[Random.new():NextInteger(1, table.getn(killtxts))]
				ui.Name = "Disabled" .. gn

				mdl:SetAttribute("DeadNotBigSurprise", true)
			else
				tb.Text = txt
			end

			ui.BBG.Size = UDim2.new(10, 0, 2, 0)

			tb.TextTransparency = 0
			tb.TextStrokeTransparency = 0

			local hrp = ep or mdl:FindFirstChild("HumanoidRootPart") or mdl:FindFirstChild("Torso")

			ui.CFrame = hrp.CFrame * CFrame.new(Random.new():NextNumber(-1, 1), Random.new():NextNumber(-1, 1), Random.new():NextNumber(-1, 1))

			local inf1 = TweenInfo.new(.5, Enum.EasingStyle.Cubic,Enum.EasingDirection.Out)
			local inf2 = TweenInfo.new(3, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

			game:GetService("TweenService"):Create(ui.BBG, inf1, {Size = UDim2.new(5, 0, 1, 0)}):Play()
			game:GetService("TweenService"):Create(tb, inf1, {Rotation = Random.new():NextNumber(-15, 15)}):Play()		

			game:GetService("TweenService"):Create(ui, inf2, {CFrame = ui.CFrame * CFrame.new(0, -4, 0)}):Play()
			game:GetService("TweenService"):Create(tb, inf2, {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
		else
			local ui = templates[gn]:Clone()
			ui.Parent = mdl

			local txt

			if math.floor(dmg) == dmg then
				txt = tostring(dmg)
			else
				txt = string.format("%.1f", tostring(dmg))
			end

			txt = string.gsub(txt, "-", "")

			local tb = ui.BBG.TextBox
			tb.Text = txt

			if mdl:FindFirstChildWhichIsA("Humanoid", true).Health <= 0 then
				tb.Text = killtxts[Random.new():NextInteger(1, table.getn(killtxts))]
				ui.Name = "Disabled" .. gn

				mdl:SetAttribute("DeadNotBigSurprise", true)
			end

			ui.BBG.Size = UDim2.new(10, 0, 2, 0)

			tb.TextTransparency = 0
			tb.TextStrokeTransparency = 0

			local hrp = ep or mdl:FindFirstChild("HumanoidRootPart")

			ui.CFrame = hrp.CFrame * CFrame.new(Random.new():NextNumber(-1, 1), Random.new():NextNumber(-1, 1), Random.new():NextNumber(-1, 1))

			local inf1 = TweenInfo.new(.5, Enum.EasingStyle.Cubic,Enum.EasingDirection.Out)
			local inf2 = TweenInfo.new(3, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

			game:GetService("TweenService"):Create(ui.BBG, inf1, {Size = UDim2.new(5, 0, 1, 0)}):Play()
			game:GetService("TweenService"):Create(tb, inf1, {Rotation = Random.new():NextNumber(-15, 15)}):Play()		

			game:GetService("TweenService"):Create(ui, inf2, {CFrame = ui.CFrame * CFrame.new(0, -4, 0)}):Play()
			game:GetService("TweenService"):Create(tb, inf2, {TextTransparency = 1, TextStrokeTransparency = 1}):Play()

			coroutine.wrap(function()
				repeat
					task.wait()
				until tb.TextTransparency >= .99

				ui:Destroy()
			end)()
		end
	end

	local function stun(hum, t)
		if t == 0 or nil then
			return
		end

		coroutine.wrap(function()
			local mdl = hum:FindFirstAncestorOfClass("Model")
			local sc = mdl:GetAttribute("StunCounter") or 0
			mdl:SetAttribute("StunCounter", sc + 1)

			local ows = hum:GetAttribute("OriginalWalkspeed") or hum.WalkSpeed
			hum:SetAttribute("OriginalWalkspeed", ows)

			hum.WalkSpeed = .5

			mdl:SetAttribute("Stunned", true)

			if not mdl:FindFirstChild("StunGUI") then
				local ui = templates.DamageGUI.BBG:Clone()
				ui.Name = "StunGUI"
				ui.Parent = mdl
				ui.TextBox.Text = "STUNNED"
				ui.ClipsDescendants = false
				ui.Size = UDim2.fromScale(3, 1.5)
				ui.Adornee = mdl.HumanoidRootPart
				ui.StudsOffset = Vector3.new(0, 3, 0)
			end

			coroutine.wrap(function()
				repeat
					hum:UnequipTools()
					task.wait()
				until mdl:GetAttribute("StunCounter") == 0
			end)()

			task.wait(t)

			if mdl:GetAttribute("StunCounter") ~= sc + 1 then
				return
			end

			mdl:SetAttribute("StunCounter", 0)

			if mdl:FindFirstChild("StunGUI") then
				mdl.StunGUI:Destroy()
			end

			if hum:FindFirstAncestorOfClass("Model") ~= nil then
				hum:FindFirstAncestorOfClass("Model"):SetAttribute("Stunned", false)
			end

			hum.WalkSpeed = ows
		end)()
	end

	local function ghit(p, n)
		local cf = p.CFrame

		local h1 = templates.HitEffects.Hit:Clone()
		local h2 = templates.HitEffects.Hit3:Clone()
		local h3 = templates.HitEffects.HitPE:Clone()

		for i = 1, 10 do
			coroutine.wrap(function()
				local lv = cf * CFrame.Angles(math.rad(Random.new():NextNumber(0, 360)), 0, math.rad(Random.new():NextNumber(0, 360)))

				local h = h1:Clone()
				h.Size = Vector3.new(Random.new():NextNumber(.1, .3), Random.new():NextNumber(1, 3), Random.new():NextNumber(.1, .3)) * 1.5
				h.CFrame = lv * CFrame.new(0, h.Size.Y / 2, 0)
				h.Parent = script

				local tw = game:GetService("TweenService"):Create(h, TweenInfo.new(.5), {CFrame = h.CFrame * CFrame.new(0, Random.new():NextNumber(3, 8), 0), Size = Vector3.new(), Transparency = 1})
				tw:Play()

				coroutine.wrap(function()
					tw.Completed:Wait()
					h:Destroy()
				end)()
			end)()
		end

		h2.CFrame = cf
		h2.Parent = script

		h3.Parent = p

		h3:Emit(n or 2)

		for _, v in ipairs(h2.Attachment:GetChildren()) do
			v.Brightness = 10
			v:Emit(25)
		end

		task.delay(.5, function()
			h2:Destroy()
			h3:Destroy()
		end)
	end

	local function hfx(t, victim, ep)
		ep = ep or victim:FindFirstChild("HumanoidRootPart")

		if t == "Freeze" then
			local f1 = templates.HitEffects.Freeze.Freeze:Clone()
			local f2 = templates.HitEffects.Freeze2.Freeze2:Clone()

			f1.Parent = ep
			f2.Parent = ep

			for _, v in pairs(f1:GetChildren()) do
				v:Emit(tonumber(v.Name))
			end

			for _, v in pairs(f2:GetChildren()) do
				v:Emit(math.floor(v.Rate / 5))
			end

			task.delay(2, f1.Destroy, f1)
			task.delay(2, f2.Destroy, f2)
		elseif t == "Light" then
			local spl = templates.HitEffects.Light:Clone()
			spl.CFrame = CFrame.new(ep.CFrame.Position, owner.Character.HumanoidRootPart.CFrame.Position) * CFrame.Angles(math.random(), math.random(), math.random())
			spl.CFrame *= CFrame.new(Random.new():NextNumber(-1, .5), Random.new():NextNumber(-.5, 1), Random.new():NextNumber(-1, .5))
			spl.Parent = script

			game:GetService("TweenService"):Create(spl, TweenInfo.new(3, Enum.EasingStyle.Cubic), {Size = Vector3.new(2, 10, 1), Transparency = 1}):Play()

			task.delay(.2, spl.Destroy, spl)
			ghit(ep)
		elseif t == "Heavy" then
			ghit(ep, 25)

			local h = templates.HitEffects.Heavy:Clone()
			h.Parent = script
			h.CFrame = ep.CFrame

			for _, v in ipairs(h.Attachment:GetChildren()) do
				v.Brightness = 10
				v:Emit(15)
			end

			task.delay(1, h.Destroy, h)
		end
	end

	local function attack(tbl, stats, scf)
		local victims = tbl
		local dist = math.huge

		if table.getn(victims) ~= 0 then
			local snd = stats.Sound or "HitSFX"

			if stats.Sound then
				if typeof(stats.Sound) == "table" then
					snd = stats.Sound[Random.new():NextInteger(1, table.getn(stats.Sound))]
				end
			end

			play(snd, scf)
		end

		local mult = 1 -- // (owner.Character:GetAttribute("Resolve") == true and 1.2 or 1)

		for _, victim in pairs(victims) do
			local hum, hrp = victim:FindFirstChildWhichIsA("Humanoid", true), victim:FindFirstChild("HumanoidRootPart", true)

			hum.Health -= (stats.Damage or 0) * mult

			dmgui(victim, stats.Damage * mult, stats.EffectPart)

			stun(hum, stats.Stun)

			if stats.Animation and hum.RigType == Enum.HumanoidRigType.R6 then
				coroutine.wrap(function()
					AnimationHandler:Animate({
						["Rig"] = victim,
						["StallTime"] = .2,
						["DisableWelds"] = true,
						["Animation"] = stats.Animation
					})
				end)()
			end

			if stats.Knockback then
				local bv = Instance.new("BodyVelocity", hrp)
				bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge) -- // Vector3.new(1, 1, 1) * stats.Knockback[1]
				bv.Velocity = (owner.Character.HumanoidRootPart.CFrame.lookVector * stats.Knockback[1]) + (stats.Knockback[3] or Vector3.new())

				task.delay(stats.Knockback[2], function()
					bv:Destroy()
				end)
			end

			coroutine.wrap(hfx)(stats.HitEffect or "Light", victim, stats.EffectPart)
		end
	end

	local function combo()
		if dbs.LMBCombo == true or dbs.Stunned == true then
			return
		end

		dbs.Stunned = true
		dbs.LMBCombo = true

		-- // play("LMBSFX" .. lmbc)
		play("LMBVoice" .. lmbc)

		local inhb = hb(owner.Character.HumanoidRootPart, CFrame.new(0, -.4, -3.3), Vector3.new(5, 5.2, 7))

		local track = AnimationHandler:Animate({
			["Speed"] = 1.5,
			["Wrapped"] = true,
			["Rig"] = owner.Character,
			["Priority"] = 2 + (lmbc / 10),
			["Animation"] = anims.LMB[tostring(lmbc)]
		})

		local clmb = lmbc

		if lmbc == 4 then
			lmbc = 1

			coroutine.wrap(function()
				attack(inhb, {
					["Stun"] = .3,
					["Damage"] = 21,
					["HitEffect"] = "Heavy",
					["Knockback"] = {60, .25}
				})
			end)()

			task.delay(cds.LMBCombo, function()
				dbs.Stunned = false
			end)

			task.delay(cds.LMBFinisher, function()
				dbs.LMBCombo = false
			end)
		else
			lmbc += 1

			coroutine.wrap(function()
				attack(inhb, {
					["Stun"] = .75,
					["Damage"] = 8,
					["Knockback"] = {5, .05}
				})
			end)()

			coroutine.wrap(function()
				local clmb = lmbc
				task.wait(1.5)

				if lmbc == clmb then
					lmbc = 1
				end
			end)()

			task.delay(cds.LMBCombo, function()
				dbs.LMBCombo = false
				dbs.Stunned = false
			end)
		end
	end

	local function seth(ws, jp)
		owner.Character.Humanoid.WalkSpeed = (ws == "OG" and 25 or ws)
		owner.Character.Humanoid.JumpPower = (jp == "OG" and 50 or jp)
	end

	local function bfx(length, stretch, offset)
		local stretch = stretch or 1
		local cf = offset or owner.Character.HumanoidRootPart.CFrame

		for _ = 1, 3 do
			local arm
			local p1, p2
			local lt = (cf * CFrame.new(0, 0, -10)).Position

			local function pgen(s)
				local rnd1

				if s == "Right" then
					rnd1 = Random.new():NextNumber(.5, 3) * stretch
				else
					rnd1 = Random.new():NextNumber(-3, -.5) * stretch
				end

				local rnd2 = Random.new():NextNumber(-.5, .5) * stretch

				local rnd3 = math.random()

				local p1 = (cf * CFrame.new(rnd1, rnd2, -2)).Position
				local p2 = (cf * CFrame.new(rnd1 * 2, rnd2 * 6, -4)).Position

				return p1, p2
			end

			if Random.new():NextInteger(1, 10) > 5 then
				local marm = owner.Character["Right Arm"]
				arm = marm:Clone()

				p1, p2 = pgen("Right")
			else
				local marm = owner.Character["Left Arm"]
				arm = marm:Clone()

				p1, p2 = pgen("Left")
			end

			local tp = Instance.new("Attachment", arm)
			tp.Position = Vector3.new(-.394, .793, .477)

			local bt = Instance.new("Attachment", arm)
			bt.Position = Vector3.new(.329, -.847, -.348)


			local trl = templates["MotionBlur" .. Random.new():NextInteger(1, 2)]:Clone()
			trl.Parent = arm
			trl.Enabled = true
			trl.Attachment0 = tp
			trl.Attachment1 = bt
			trl.Color = ColorSequence.new(arm.Color)
			trl.Transparency = NumberSequence.new(0, 1)

			-- // arm.Trail.Transparency = NumberSequence.new(0, 1)

			local i = 0

			arm.Anchored = true
			arm.Parent = script
			arm.Transparency = 0

			local cnt
			local length = length or .7

			local rate = 1 / length

			coroutine.wrap(function()
				task.wait(.2)

				for _, v in pairs(arm:GetChildren()) do
					if v:IsA("BasePart") then
						game:GetService("TweenService"):Create(v, TweenInfo.new(.2), {Transparency = 1}):Play()
					end
				end

				game:GetService("TweenService"):Create(arm, TweenInfo.new(.2), {Transparency = 1}):Play()

				trl.Enabled = false
				task.wait(.25)

				arm:Destroy()
			end)()

			local function bezier(p1, p2, p3, t)
				return (1 - t) ^ 2 * p1 + 2 * (1 - t) * t * p2 + t ^ 2 * p3
			end

			cnt = game:GetService("RunService").Heartbeat:Connect(function(dt)
				i = i + dt * rate

				if i > 1 then
					cnt:Disconnect()
					i = 1
				end

				if i + dt * rate <= .8 then
					local v = game:GetService("TweenService"):GetValue(i, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)

					local nv = game:GetService("TweenService"):GetValue(i + dt * rate, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)

					local p = bezier(p1, p2, lt, v)
					local np = bezier(p1, p2, lt, nv)

					arm.CFrame = CFrame.new(p, np) * CFrame.Angles(math.pi / 2, 0, 0)
				else
					local v = game:GetService("TweenService"):GetValue(i, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)

					local p = bezier(p1, p2, lt, v)
					arm.CFrame = CFrame.new(p, lt) * CFrame.Angles(math.pi / 2, 0, 0)
				end
			end)
		end
	end

	local function barrage()
		if dbs.Barrage == true or dbs.Stunned == true then
			return
		end

		seth(8, 0)
		dbs.Barrage = true
		dbs.Stunned = true

		local speed = 1

		play("BarrageStartup")

		local tr = AnimationHandler:Animate({
			["Speed"] = 2.25,
			["Priority"] = 3,
			["Wrapped"] = true,
			["Rig"] = owner.Character,
			["Animation"] = anims.Barrage.Startup
		})

		tr:GetMarkerReachedSignal("Hit"):Connect(function()
			local inhb = hb(owner.Character.HumanoidRootPart, CFrame.new(0, -.4, -3.3), Vector3.new(5, 5.2, 7))

			attack(inhb, {
				["Stun"] = .75,
				["Damage"] = 5,
				["Knockback"] = {5, .05},
				["Sound"] = "BarrageHitSFX1"
			})
		end)

		tr.Stopped:Wait()

		play("BarrageVoice")

		AnimationHandler:Animate({
			["Speed"] = 2,
			["Priority"] = 3.5,
			["Looping"] = true,
			["Wrapped"] = true,
			["Rig"] = owner.Character,
			["Animation"] = anims.Barrage.Loop
		})

		local t = tick()

		repeat
			coroutine.wrap(function()
				play("SwingLMB")

				local inhb = hb(owner.Character.HumanoidRootPart, CFrame.new(0, -.4, -3.3), Vector3.new(5, 5.2, 7))

				attack(inhb, {
					["Stun"] = .5,
					["Damage"] = 1.5,
					["Knockback"] = {5, .05},
					["Sound"] = {"BarrageHitSFX1", "BarrageHitSFX2"}
				})

				-- // bfx()
			end)()

			task.wait(.1 / speed)
		until tick() - t >= (3 / speed) or dbs.EHeld == false

		AnimationHandler:Stop({
			["FadeTime"] = 0,
			["Wrapped"] = true,
			["Rig"] = owner.Character,
			["Animation"] = anims.Barrage.Loop
		})

		local tr = AnimationHandler:Animate({
			["Priority"] = 4,
			["Speed"] = speed,
			["Wrapped"] = true,
			["Rig"] = owner.Character,
			["Animation"] = anims.Barrage.End
		})

		task.wait(.3)
		local inhb = hb(owner.Character.HumanoidRootPart, CFrame.new(0, -.4, -3.3), Vector3.new(5, 5.2, 7))

		attack(inhb, {
			["Stun"] = .2,
			["Damage"] = 16,
			["Sound"] = "HeavyHitSFX",
			["Knockback"] = {60, .25}
		})

		tr.Stopped:Wait()

		seth("OG", "OG")
		dbs.Stunned = false

		task.delay(cds.Barrage, function()
			dbs.Barrage = false
		end)
	end

	local function bloodsuck()
		if dbs.BloodSuck == true or dbs.Stunned == true then
			return
		end

		dbs.Stunned = true
		dbs.BloodSuck = true

		local track = AnimationHandler:Animate({
			["Priority"] = 3,
			["Wrapped"] = true,
			["Rig"] = owner.Character,
			["Animation"] = anims.BloodSuck.Startup
		})

		seth(8, 0)
		play("BloodSuckTry")

		task.wait(.3)

		local inhb = hb(owner.Character.HumanoidRootPart, CFrame.new(0, 0, -3), Vector3.new(6, 10, 6))

		local victim
		local dist = math.huge

		for _, v in pairs(inhb) do
			local magn = (v.HumanoidRootPart.Position - owner.Character.HumanoidRootPart.Position).Magnitude

			if magn < dist then
				victim = v
				dist = magn
			end
		end

		if victim then
			owner.Character.Humanoid.AutoRotate = false

			AnimationHandler:Stop({
				["FadeTime"] = 0,
				["Rig"] = owner.Character,
				["Animation"] = anims.BloodSuck.Startup
			})

			local plr = game:GetService("Players"):GetPlayerFromCharacter(victim)

			if victim:FindFirstChildWhichIsA("Humanoid", true).RigType == Enum.HumanoidRigType.R15 and plr then
				local id = plr.UserId
				plr.CharacterAppearanceId = 32065

				local old = plr.Character.HumanoidRootPart.CFrame
				plr:LoadCharacter()
				plr.Character.HumanoidRootPart.CFrame = old
				plr.Character.Humanoid:ApplyDescription(game:GetService("Players"):GetHumanoidDescriptionFromUserId(id))
				task.wait()

				plr.CharacterAppearanceId = id
				victim = plr.Character
			end

			task.wait()

			AnimationHandler:ToggleWelds(victim, false, true)

			AnimationHandler:Animate({
				["Wrapped"] = true,
				["Priority"] = 3.5,
				["Rig"] = owner.Character,
				["Animation"] = anims.BloodSuck.Hit
			})

			AnimationHandler:Animate({
				["Rig"] = victim,
				["Wrapped"] = true,
				["Animation"] = anims.BloodSuck.Victim,
				["DisableWelds"] = (not victim:GetAttribute("Vampire") or true)
			})

			setgroup(victim, "FX")
			setgroup(owner.Character, "FX")

			victim:SetAttribute("Stunned", true)

			local function bsuck()
				owner.Character.Humanoid.Health += 20

				dmgui(owner.Character, -15)

				local function highlight(v, c)
					if v:IsA("BasePart") then
						local h = Instance.new("Highlight", v)
						h.Adornee = v
						h.FillColor = c
						h.FillTransparency = 0
						h.DepthMode = "Occluded"
						h.OutlineTransparency = 1

						game:GetService("TweenService"):Create(h, TweenInfo.new(.5), {FillTransparency = 1}):Play()

						task.delay(.5, h.Destroy, h)
					end
				end

				for _, v in pairs(victim:GetDescendants()) do
					highlight(v, Color3.new(1, 0, 0))
				end

				for _, v in pairs(owner.Character:GetDescendants()) do
					highlight(v, Color3.new(0, 1, 0))
				end

				attack({victim}, {
					["Stun"] = 0,
					["Sound"] = "",
					["Damage"] = 10,
					["HitEffect"] = "",
					["EffectPart"] = (victim:FindFirstChild("Torso") or vicitm:FindFirstChild("UpperTorso"))
				})
			end

			stun(victim:FindFirstChildWhichIsA("Humanoid", true), 4)

			for i = 1, 250 do
				if i == 40 then
					play("BloodSuckHit")

					bsuck()
				elseif i == 120 or i == 180 then
					bsuck()
				end

				if victim.Parent == nil then
					break
				end

				victim.HumanoidRootPart.Anchored = true
				owner.Character.HumanoidRootPart.Anchored = true
				victim.HumanoidRootPart.CFrame = owner.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, -1) * CFrame.Angles(0, math.pi, 0)

				task.wait()
			end


			seth("OG", "OG")
			setgroup(owner.Character, "Default")

			owner.Character.Humanoid.AutoRotate = true
			owner.Character.HumanoidRootPart.Anchored = false

			dbs.Stunned = false

			task.delay(cds.BloodSuck, function()
				dbs.BloodSuck = false
			end)

			if victim.Parent == nil then
				return
			end

			victim:SetAttribute("Stunned", false)

			victim.Humanoid.AutoRotate = true
			victim.HumanoidRootPart.Anchored = false


			local bv = Instance.new("BodyVelocity", victim.HumanoidRootPart)
			bv.P = math.huge
			bv.MaxForce = Vector3.new(1000000, 1000000, 1000000)
			bv.Velocity = owner.Character.HumanoidRootPart.CFrame.lookVector * 75
			task.delay(.25, bv.Destroy, bv)

			setgroup(victim, "Default")
		else
			track.Stopped:Wait()

			dbs.Stunned = false
			seth("OG", "OG")

			task.delay(cds.BloodSuck, function()
				dbs.BloodSuck = false
			end)
		end
	end

	local function freezecounter()
		if dbs.Stunned == true or dbs.FreezeCounter == true then
			return
		end

		seth(0, 0)

		dbs.Stunned = true
		dbs.FreezeCounter = true

		local idle = AnimationHandler:Animate({
			["Priority"] = 3,
			["StallTime"] = 3,
			["Wrapped"] = true,
			["Rig"] = owner.Character,
			["Animation"] = anims.FreezeCounter.Idle
		})

		local highlights = {}

		for _, v in pairs(owner.Character:GetDescendants()) do
			if v:IsA("BasePart") then
				local h = Instance.new("Highlight", v)
				h.Adornee = v
				h.FillTransparency = .65
				h.DepthMode = "Occluded"
				h.OutlineTransparency = .65
				h.FillColor = Color3.new(1, 0, 0)
				h.OutlineColor = Color3.new(.75, 0, 0)

				table.insert(highlights, h)
			end
		end

		local cnt
		local fdb = false
		local ohp = owner.Character.Humanoid.Health

		owner.Character.Humanoid.MaxHealth = 100000
		owner.Character.Humanoid.Health = 100000

		play("FreezeCounterIdle")

		local bl = {}

		cnt = owner.Character.Humanoid.HealthChanged:Connect(function(nhp)
			if fdb == false then
				local inhb = hb(owner.Character.HumanoidRootPart, CFrame.new(), Vector3.new(10, 10, 10), bl)

				local victim
				local dist = math.huge

				for _, v in pairs(inhb) do
					local magn = (v.HumanoidRootPart.Position - owner.Character.HumanoidRootPart.Position).Magnitude

					if magn < dist then
						victim = v
						dist = magn
					end
				end

				if victim and fdb == false then
					for _, v in pairs(highlights) do
						game:GetService("TweenService"):Create(v, TweenInfo.new(.5), {FillTransparency = 1, OutlineTransparency = 1}):Play()
						task.delay(.5, v.Destroy, v)
					end

					if cnt then
						cnt:Disconnect()
					end

					fdb = true
					bl = {workspace}

					play("SwingLMB")
					play("FreezeCounterPlayer")

					owner.Character.Humanoid.MaxHealth = (0 / 0)
					owner.Character.Humanoid.Health = (0 / 0)

					setgroup(victim, "FX")
					setgroup(owner.Character, "FX")

					victim.Humanoid.AutoRotate = false
					victim.HumanoidRootPart.Anchored = true

					owner.Character.Humanoid.AutoRotate = false
					owner.Character.HumanoidRootPart.Anchored = true

					victim.HumanoidRootPart.CFrame = owner.Character.HumanoidRootPart.CFrame * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0, 6)

					AnimationHandler:ToggleWelds(victim, false, true)

					local track = AnimationHandler:Animate({
						["Priority"] = 4,
						["Wrapped"] = true,
						["Rig"] = owner.Character,
						["Animation"] = anims.FreezeCounter.Player
					})

					AnimationHandler:Animate({
						["Priority"] = 4,
						["Rig"] = victim,
						["Wrapped"] = true,
						["DisableWelds"] = (not victim:GetAttribute("Vampire") or true),
						["Animation"] = anims.FreezeCounter.Victim[victim.Humanoid.RigType.Name]
					})

					AnimationHandler:Stop({
						["FadeTime"] = 0,
						["Rig"] = owner.Character,
						["Animation"] = idle.Animation
					})

					track:GetMarkerReachedSignal("Freeze"):Connect(function()
						attack({victim}, {
							["Stun"] = 3,
							["Damage"] = 20,
							["HitEffect"] = "Freeze",
							["Sound"] = "FreezeCounterSFX",
							["EffectPart"] = (victim:FindFirstChild("Torso") or victim:FindFirstChild("UpperTorso"))
						})

						for _, v in pairs(victim:GetDescendants()) do
							if v:IsA("BasePart") then
								v.Anchored = true

								local h = Instance.new("Highlight", v)
								h.Adornee = v
								h.FillTransparency = 0
								h.DepthMode = "Occluded"
								h.OutlineTransparency = 0
								h.FillColor = Color3.fromRGB(133, 243, 255)
								h.OutlineColor = Color3.new(0, 0, 1)

								task.delay(3, function()
									v.Anchored = false
									victim.Humanoid.AutoRotate = true

									game:GetService("TweenService"):Create(h, TweenInfo.new(.5), {FillTransparency = 1, OutlineTransparency = 1}):Play()
									task.delay(.5, h.Destroy, h)
								end)
							end
						end
					end)

					track.Stopped:Wait()

					seth("OG", "OG")

					setgroup(victim, "Default")
					setgroup(owner.Character, "Default")

					owner.Character.Humanoid.MaxHealth = 450
					owner.Character.Humanoid.Health = ohp

					owner.Character.Humanoid.AutoRotate = true
					owner.Character.HumanoidRootPart.Anchored = false

					dbs.Stunned = false
					task.delay(cds.FreezeCounter, function()
						dbs.FreezeCounter = false
					end)
				end
			end
		end)

		task.wait(3)

		AnimationHandler:Stop({
			["FadeTime"] = .5,
			["Rig"] = owner.Character,
			["Animation"] = idle.Animation
		})

		local old = fdb

		if cnt then
			fdb = true
			cnt:Disconnect()
		end

		if old == false then
			for _, v in pairs(highlights) do
				game:GetService("TweenService"):Create(v, TweenInfo.new(.5), {FillTransparency = 1, OutlineTransparency = 1}):Play()
				task.delay(.5, v.Destroy, v)
			end

			seth("OG", "OG")

			owner.Character.Humanoid.MaxHealth = 450
			owner.Character.Humanoid.Health = ohp

			dbs.Stunned = false
			task.delay(cds.FreezeCounter, function()
				dbs.FreezeCounter = false
			end)
		end
	end

	local function taunt(data)
		local h = owner.Character.Head

		local ui

		if not h:FindFirstChild("Taunt") then
			ui = templates.Taunt:Clone()
			ui.Parent = h
			ui.TextBox.Text = ""
			ui.TextBox.TextTransparency = 1
		else
			ui = h:FindFirstChild("Taunt")
		end

		if ui and ui.TextBox.Text ~= "" then
			return
		end

		game:GetService("TweenService"):Create(ui.TextBox, TweenInfo.new(.5), {TextTransparency = 0}):Play()

		local snd = Instance.new("Sound", owner.Character.Head)
		snd.SoundId = data.SoundId
		snd.RollOffMinDistance = 20
		snd.RollOffMaxDistance = 200
		snd.Volume = data.Volume or .75
		snd.RollOffMode = "InverseTapered"

		if data.SoundId ~= "" then
			repeat
				task.wait()
			until snd.TimeLength > 0
		end

		if snd.TimeLength > 0 and data.SoundId ~= "" then
			snd:Play()
			task.delay(snd.TimeLength + 1, snd.Destroy, snd)
		end

		for i = 1, string.len(data.Text) do
			task.wait(.03)
			ui.TextBox.Text = string.sub(data.Text, 1, i)

			if data.Timings ~= nil then
				for part, time in pairs(data.Timings) do
					-- // print(ui.TextBox.Text, part, ui.TextBox.Text == part)
					if ui.TextBox.Text == part then
						-- // data.Timings[part] = nil
						task.wait(time)
					end
				end
			end
		end

		task.wait(data.StallTime or 1.5)

		ui.TextBox.TextTransparency = 0
		ui.TextBox.Text = ""
		snd:Destroy()
	end

	local function zombie(desc, cf, n)
		local replace = false

		for i, v in pairs(zombies) do
			if v[1] == "ToBeReplaced" then
				zi = v[4]
				ox = v[2]
				oz = v[3]

				replace = true
				break
			end
		end

		if replace == false then
			zi += 1

			ox += (w / 4)

			if ox > (w / 2) then
				oz += 1
				ox = -(w / 2)
			end
		end

		local color = BrickColor.new("Dark green").Color

		local zomb = game:GetService("Players"):CreateHumanoidModelFromDescription(desc, "R6")
		zomb.Name = n
		zomb.Parent = script
		zomb:WaitForChild("Humanoid").DisplayName = n
		zomb:WaitForChild("HumanoidRootPart").CFrame = cf

		zomb.Humanoid.AutoRotate = false

		zomb:SetAttribute("X", ox)
		zomb:SetAttribute("Z", oz)
		zomb:SetAttribute("Number", zi)
		zomb.Humanoid:SetAttribute("Zombie", true)

		local ao = Instance.new("AlignOrientation", zomb.HumanoidRootPart)
		ao.Attachment1 = zat
		ao.Responsiveness = 200
		ao.MaxTorque = math.huge
		ao.MaxAngularVelocity = math.huge
		ao.Attachment0 = Instance.new("Attachment", ao.Parent)

		local animate = Instance.new("Script", zomb)
		animate.Name = "Animate"

		coroutine.wrap(function()
			pcall(sandbox(animate, r6))
		end)()

		setgroup(zomb, "Zombies")

		local ozi = zi
		local oox, ooz = ox, oz
		local cf = CFrame.new(ox * s, 0, 5 + (oz * s))

		zombies[zi] = {zomb, cf, zi}

		local bc = zomb:FindFirstChild("Body Colors")

		if bc then
			bc.HeadColor3 = color
			bc.TorsoColor3 = color
			bc.LeftArmColor3 = color
			bc.LeftLegColor3 = color
			bc.RightArmColor3 = color
			bc.RightLegColor3 = color
		end

		zomb.Humanoid.Died:Connect(function()
			task.delay(3, zomb.Destroy, zomb)
			zombies[ozi] = {"ToBeReplaced", oox, ooz, ozi}
		end)

		return zomb
	end

	re.OnServerEvent:Connect(function(plr, args)
		if owner.Character:GetAttribute("Stunned") == true then
			return
		end

		if args.Action == "Update" then
			dbs.EHeld = args.EHeld
		elseif args.Action == "HP" then
			local hp = owner.Character.Health
			hp.Disabled = not hp.Disabled

			print("Healing: " .. hp.Enabled)
		elseif args.Action == "M1" then
			combo()
		elseif args.Action == "Barrage" then
			barrage()
		elseif args.Action == "BloodSuck" then
			bloodsuck()
		elseif args.Action == "FreezeCounter" then
			freezecounter()
		elseif args.Action == "Taunt" then
			if dbs.Taunt == true then
				return
			end

			dbs.Taunt = true

			taunt(taunts[Random.new():NextInteger(1, table.getn(taunts))])

			task.delay(cds.Taunt, function()
				dbs.Taunt = false
			end)
		end
	end)

	AnimationHandler:Animate({
		["Speed"] = 1,
		["Priority"] = 1,
		["Wrapped"] = true,
		["Looping"] = true,
		["Rig"] = owner.Character,
		["Animation"] = anims.Idle
	})

	owner.Character.Humanoid.Running:Connect(function(spd)
		AnimationHandler:ToggleWelds(owner.Character, false, true)

		if spd > .1 then
			if dbs.Idle == false and AnimationHandler._Animations[owner.Character][anims.Run] == nil then
				dbs.Idle = true

				AnimationHandler:Animate({
					["Speed"] = 1,
					["Priority"] = 2,
					["Wrapped"] = true,
					["Looping"] = true,
					["Rig"] = owner.Character,
					["Animation"] = anims.Run
				})
			end
		elseif spd < .1 then
			dbs.Idle = false

			AnimationHandler:Stop({
				["FadeTime"] = .1,
				["Rig"] = owner.Character,
				["Animation"] = anims.Run
			})
		end
	end)

	coroutine.wrap(function()
		while true do
			task.wait()

			for _, v in pairs(zombies) do
				if typeof(v[1]) == "Instance" then
					local hum = v[1]:FindFirstChildWhichIsA("Humanoid", true)

					if hum then
						hum:MoveTo((owner.Character.HumanoidRootPart.CFrame * v[2]).Position)
					end
				end
			end
		end
	end)()

	-- [[ MAIN LOOP ]] --

	coroutine.wrap(function()
		while true do
			task.wait()

			local params = OverlapParams.new()
			params.FilterDescendantsInstances = {owner.Character, script}
			params.FilterType = Enum.RaycastFilterType.Blacklist

			for _, v in pairs(workspace:GetPartBoundsInRadius(owner.Character.HumanoidRootPart.Position, 25, params)) do
				local hum = findhum(v)

				if hum then
					if hum.Health <= 0 and hum:GetAttribute("Zombie") ~= true then
						zombie(hum:GetAppliedDescription(), hum.RootPart.CFrame, "Zombie " .. hum.DisplayName)
						v:FindFirstAncestorOfClass("Model"):Destroy()
					end
				end
			end
		end
	end)()
end

mask.Activated:Connect(function()
	if db == true or mask.Parent:GetAttribute("Vampire") == true then
		return
	end

	db = true

	local char = mask.Parent
	local hum = char.Humanoid

	local plr = game:GetService("Players"):GetPlayerFromCharacter(char)

	if plr == nil then
		db = false

		return
	end

	local ort = hum.RigType.Name

	if ort == "R15" then
		local id = plr.UserId
		plr.CharacterAppearanceId = 32065

		local old = plr.Character.HumanoidRootPart.CFrame

		mask.Parent = nil

		plr:LoadCharacter()
		plr.Character.HumanoidRootPart.CFrame = old
		plr.Character.Humanoid:ApplyDescription(game:GetService("Players"):GetHumanoidDescriptionFromUserId(id))
		task.wait()

		mask.Parent = plr.Character

		plr.CharacterAppearanceId = id

		char = plr.Character
		hum = char:WaitForChild("Humanoid")
	end

	task.wait()

	local owner = plr

	local nls = NLS([[
        script:WaitForChild("CameraEvent"):FireServer()
        
        local re = script.CameraEvent
        local cam = workspace.CurrentCamera
    
        -- // script.Parent = workspace
        
        re.OnClientEvent:Connect(function(what)
            if what == "Camera" then
                cam.CameraType = Enum.CameraType.Scriptable

                repeat
                    game:GetService("RunService").RenderStepped:Wait()
                    cam.CFrame = re.CameraCFrame.Value
                until re.StopCamera.Value == true
    
                cam.CameraType = Enum.CameraType.Custom
            end
        end)
    ]], plr.Character)

	local ran = false

	local re = Instance.new("RemoteEvent", nls)
	re.Name = "CameraEvent"

	local vl = Instance.new("CFrameValue", re)
	vl.Name = "CameraCFrame"
	vl.Value = CFrame.new()

	local vl = Instance.new("BoolValue", re)
	vl.Name = "StopCamera"
	vl.Value = false

	local thread = task.spawn(function()
		re.OnServerEvent:Wait()
		ran = true
	end)

	repeat
		task.wait()
	until ran == true or nls.Parent == nil

	if nls.Parent == nil then
		task.cancel(thread)
		return
	end

	local snd = play("MaskUse", hum.RootPart)
	task.wait(.5)

	hum.WalkSpeed = 0
	hum.JumpPower = 0

	hum.RootPart.Anchored = true


	local track = AnimationHandler:Animate({
		["Rig"] = char,
		["StallTime"] = 2.5,
		["Wrapped"] = true,
		["Animation"] = use
	})

	local cr = templates.MaskUseCameraRig:Clone()
	cr.Parent = script

	cr.Root.CanCollide = false
	cr.Root.CanTouch = false
	cr.Root.CanQuery = false

	cr.Cam.CanCollide = false
	cr.Cam.CanTouch = false
	cr.Cam.CanQuery = false

	cr.Root.Neck.C1 = CFrame.new(0, -.5, 0)
	cr.Root.Neck.C0 = CFrame.new(0, .5, 0) * CFrame.Angles(0, math.pi, 0)

	AnimationHandler:Animate({
		["Rig"] = cr,
		["StallTime"] = 3,
		["Wrapped"] = true,
		["Animation"] = usecam
	})

	re:FireClient(plr, "Camera")

	local done = false
	re.StopCamera.Value = false

	coroutine.wrap(function()
		while task.wait() and done == false do
			re.StopCamera.Value = false
			re.CameraCFrame.Value = cr.Cam.CFrame
			cr.Root.CFrame = hum.RootPart.CFrame * CFrame.Angles(0, math.pi, 0)
		end
	end)()

	coroutine.wrap(function()
		track.Stopped:Wait()
		done = true
		re.StopCamera.Value = true
		cr:Destroy()
	end)()

	local mh = mask.Handle:Clone()

	track:GetMarkerReachedSignal("Eyes"):Connect(function()
		-- // play("Laugh", hum.RootPart)
		-- // play("MaskActivate", hum.RootPart)

		mh.Eye1.EyeEffect1.Enabled = true
		mh.Eye1.EyeEffect2.Enabled = true

		mh.Eye2.EyeEffect1.Enabled = true
		mh.Eye2.EyeEffect2.Enabled = true
	end)

	track:GetMarkerReachedSignal("Effects"):Connect(function()
		for _, v in pairs(mh:GetChildren()) do
			if v.Name == "FX" then
				v.PE:Emit(10)
				v.PE.Enabled = true
			end
		end
	end)

	track:GetMarkerReachedSignal("GroundHit"):Connect(function()
		-- // play("GroundHit", hum.RootPart)
	end)

	track:GetMarkerReachedSignal("Weld"):Connect(function()
		-- // play("Attach", hum.RootPart)

		for _, v in pairs(mask:GetDescendants()) do
			if v:IsA("BasePart") then
				v.Transparency = 1
			end
		end

		local bs = templates.BloodSpill:Clone()
		bs.Parent = mh

		task.delay(3, bs.Destroy, bs)

		mh.Parent = script
		mh.Attach.PE:Emit(1)
		mh.Spikes.Transparency = 0
		mh.MaskHead.Part1 = char.Head
	end)

	track.Stopped:Wait()

	mask.Parent = workspace

	for _, v in pairs(mask:GetDescendants()) do
		if v:IsA("BasePart") and v.Name ~= "Spikes" then
			v.Transparency = 0
		end
	end

	mh:Destroy()

	local cf = char.HumanoidRootPart.CFrame

	if ort == "R15" then
		local id = plr.UserId
		plr.CharacterAppearanceId = 32065

		plr:LoadCharacter()
		plr.Character:WaitForChild("HumanoidRootPart").CFrame = cf
		plr.Character:WaitForChild("Humanoid"):ApplyDescription(game:GetService("Players"):GetHumanoidDescriptionFromUserId(id))
		task.wait()

		plr.CharacterAppearanceId = id
	else
		plr:LoadCharacter()
		plr.Character:WaitForChild("HumanoidRootPart").CFrame = cf
	end

	coroutine.wrap(load)(plr)
	db = false
end)

local cnt

cnt = owner.Chatted:Connect(function(msg)
	if msg == "load/vamp" then
		if cnt then
			cnt:Disconnect()
		end

		coroutine.wrap(load)(owner)
	end
end)
