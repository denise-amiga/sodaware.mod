' ------------------------------------------------------------
' -- src/soda_file.bmx
' -- 
' -- Type that represents a single SODA file. A SODA file is made up of fields
' -- and groups.
' --
' -- This file is part of sodaware.mod (https://www.sodaware.net/sodaware.mod/)
' -- Copyright (c) 2009-2017 Phil Newton
' --
' -- See LICENSE for full license information.
' ------------------------------------------------------------------------------


SuperStrict

Import brl.linkedlist
Import brl.map

Import sodaware.blitzmax_ascii

Import "soda_file_util.bmx"
Import "soda_group.bmx"
Import "soda_file_exceptions.bmx"

Include "soda_file_loader.bmx"


Type SodaFile
	
	' TODO: Replace _groups with an objectbag?
	Field _groups:TList     = New TList	    '''< Internal list of of groups in this file
	Field _queryCache:TMap  = New TMap      '''< Internal cache of query results
	
	
	' ------------------------------------------------------------
	' -- Helper Functions
	' ------------------------------------------------------------
	
	''' <summary>Get all top-level groups in the SodaFile document.</summary>
	''' <returns>TList of SodaGroup objects.</returns>
	Method getGroups:TList()
		Return Self._groups
	End Method

	''' <summary>Get a group at a specific index.</summary>
	''' <param name="index">The index to retrieve.</param>
	''' <returns>The group at the index, or null if not found.</returns>
	Method getGroupAtIndex:SodaGroup(index:Int)
		Return SodaGroup(Self._groups.ValueAtIndex(index))
	End Method

	''' <summary>Count the number of groups in this SodaFile.</summary>
	''' <returns>The number of groups.</returns>
	Method countGroups:Int()
		Return Self._groups.Count()
	End Method
	
	
	' ------------------------------------------------------------
	' -- Query Helpers
	' ------------------------------------------------------------
	
	''' <summary>Get the boolean value of a query.</summary>
	''' <param name="qry">The query to execute.</param>
	''' <returns>True if queried value is >=1 or equals the string "true".</returns>
	Method queryBool:Byte(qry:String)
		Local val:String = String(Self.query(qry))
		If Int(val) >= 1 Then Return True
		Return (Lower(val) = "true") 
	End Method
	
	''' <summary>Get the integer value of a query.</summary>
	''' <param name="qry">The query to execute.</param>
	''' <returns>Query result as an integer value.</returns>
	Method queryInt:Int(qry:String)
		Local val:String = String(Self.query(qry))
		Return Int(val.ToString())
	End Method
	
	''' <summary>Get the floating point value of a query.</summary>
	''' <param name="qry">The query to execute.</param>
	''' <returns>Query result as a floating point value.</returns>
	Method queryFloat:Float(qry:String)
		Local val:String = String(Self.query(qry))
		Return Float(val.ToString())
	End Method
	
	''' <summary>Get the string value of a query.</summary>
	''' <param name="qry">The query to execute.</param>
	''' <returns>Query result as a string value.</returns>
	Method queryString:String(qry:String)
		Return String(Self.query(qry))
	End Method
	
	
	' ------------------------------------------------------------
	' -- Query Functions
	' ------------------------------------------------------------
	
	''' <summary>
	''' Run a query on this SodaFile.
	'''
	''' Use dots to access child attributes, and square brackets to access
	''' an offset in an array.
	'''
	''' Returns either a group or the value of a field.
	''' </summary>
	''' <param name="qry">The query to execute.</param>
	''' <returns>Null for invalid queries, or a group/field value.</returns>
	Method query:Object(qry:String)
		
		' Check query is valid.
		If qry = "" Then Return Null
		
		' If the value is in the cache, return it instead of running the query.
		Local cachedValue:Object = Self._queryCache.ValueForKey(qry)
		If cachedValue Then Return cachedValue
		
		' Split the query into identifier chunks.
		Local identifiers:String[] = qry.Split(".")
		Local rootGroup:SodaGroup = Self.getGroup(SodaFile_Util.GetName(identifiers[0]), SodaFile_Util.GetOffset(identifiers[0]))
		
		' Return an empty result ff no valid base group was found.
		If rootGroup = Null Then Return Null
		
		' Store the found value in the query cache and return it.
		Local value:Object = rootGroup.Query(SodaFile_Util.AssembleQuery(identifiers))
		Self._queryCache.Insert(qry, value)
		Return value
		
	End Method
	
	''' <summary>Get a list of all nodes that match a query.</summary>
	''' <param name="qry">The query to run.</param>
	''' <returns>A list of found nodes.</returns>
	Method getNodes:TList(qry:String)
		
		Local nodes:TList
	
		If qry.Contains("[") Then
			
			Local conditions:TMAP = New TMap
			
			' Get key/value pairs
			qry = Mid(qry, 2, qry.Length - 2)
			
			' Field name contains meta data
			Local fields:String[] = qry.Split(",")
		
			' Go through fields, splitting into names / meta
			For Local fieldPair:String = EachIn fields
				Local pairs:String[] = fieldPair.Split(":")
				conditions.Insert(pairs[0].ToLower().Trim(), pairs[1].Trim())
			Next
			
			' Evaluate every node
			For Local group:SodaGroup = EachIn Self._groups
				
				Local validKey:Int = True
				For Local key:String = EachIn conditions.Keys()
					If group.GetMeta(key) <> String(conditions.ValueForKey(key)) Then
						validKey = False
						Exit
					EndIf
				Next
				
				If validKey Then
					If nodes = Null Then nodes = New TList
					nodes.AddLast(group)
				EndIf
				
			Next
			
		End If
		
		Return nodes
		
	End Method

	''' <summary>Get a group from a SodaFile by its identifier.</summary>
	''' <param name="name">The name of the group to retrieve. Case-sensitive.</param>
	''' <param name="offset">Optional offset to retrieve if group is an array. Use -1 to ignore.</param>
	''' <returns>The found group, or Null if not found.</returns>
	Method getGroup:SodaGroup(name:String, offset:Int = -1)
		
		Local currentOffset:Int = 0
	
		For Local group:SodaGroup = EachIn Self._groups
			If group.Identifier = name Then
				If False = group._isArray Or offset = -1 Then Return group
				If currentOffset = offset Then Return group

				currentOffset:+ 1
			EndIf
		Next

		Return Null

	End Method
	
	Function _getGroupName:String(path:String)
		Local names:String[] = path.Split(".")
		Local name:String    = ""
		For Local i:Int = 0 To names.Length - 2
			name:+ names[i] + "."
		Next
		
		' Strip last . and return
		Return Left(name, name.Length - 1)
	End Function

	Function _getFieldName:String(path:String)
		Local names:String[] = path.Split(".")
		Return names[names.Length - 1]
	End Function
	
	
	' ------------------------------------------------------------
	' -- Load functions
	' ------------------------------------------------------------
	
	Function Load:SodaFile(url:Object)
		Return SodaFile_Loader.load(url)
	End Function
	
	Function LoadFromString:SodaFile(contents:String)
		Local data:TBank = TBank.Create(contents.Length)
		For Local char:Int = 0 To contents.Length - 1
			data.PokeByte(char, contents[char])
		Next
		Return SodaFile.Load(ReadStream(data))
	End Function

	Method setValue(path:String, value:String)
		
		' First we try and get the variable
		Local parent:Object = Self.Query(path)
		If SodaGroup(parent) Then Throw "Cannot set value for entire group '" + path + "'"
		
		' Get the group and field name
		Local groupName:String 	= SodaFile._getGroupName(path)
		Local fieldName:String	= SodaFile._getFieldName(path)
		
		' Get the group
		Local group:SodaGroup	= Self.GetGroup(groupName)
		If group <> Null Then 
			group.AddField(fieldName, value)
		Else
			group = New SodaGroup
			group.SetIdentifier(groupName)
			group.AddField(fieldName, value)
			Self.addGroup(group)
		EndIf
			
	End Method
	
	
	' ------------------------------------------------------------
	' -- Internal methods
	' ------------------------------------------------------------
	
	Method addGroup(group:SodaGroup)
		If group Then Self._groups.addLast(group)
	End Method
	
	''' <summary>Resets the internal cache.</summary>
	Method resetCache()
		Self._queryCache.Clear()
	End Method
	
End Type
