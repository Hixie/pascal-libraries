{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit typedump;

interface

uses
   typinfo;

function GetDumpedTypeInfo(Root: PTypeInfo; Indent: RawByteString = ''): RawByteString;

type
   TIdentifiers = array of RawByteString;

generic function ParseEnumValue<T>(const Identifier: RawByteString; out Value: T): Boolean;
generic function ListValues<T>(): TIdentifiers;
generic function SetToStrings<T>(Values: T): TIdentifiers;
generic function SetToString<T>(Values: T): RawByteString;
generic function EnumToString<T>(Value: T): RawByteString;

implementation

uses
   sysutils;

function AlignToPtr(P: Pointer): Pointer; inline;
begin
   {$IFDEF FPC_REQUIRES_PROPER_ALIGNMENT}
     Result := Align(P,SizeOf(P));
   {$ELSE FPC_REQUIRES_PROPER_ALIGNMENT}
     Result := P;
   {$ENDIF FPC_REQUIRES_PROPER_ALIGNMENT}
end;

function GetNextShortString(const Current: PShortString): PShortString;
begin
   Result := PShortString(AlignToPtr(Pointer(Current)+Length(Current^)+1));
end;

generic function ParseEnumValue<T>(const Identifier: RawByteString; out Value: T): Boolean;
var
   Ordinal: Integer;
begin
   Ordinal := GetEnumValue(TypeInfo(T), Identifier);
   Result := Ordinal >= 0;
   if (Result) then
      Value := T(Ordinal);
end;

generic function ListValues<T>(): TIdentifiers;
var
   Index: Cardinal;
begin
   Assert(Ord(High(T)) >= 1);
   SetLength(Result, Ord(High(T)) + 1); {BOGUS Warning: Function result variable of a managed type does not seem to be initialized}
   for Index := Ord(Low(T)) to Ord(High(T)) do
      Result[Index] := GetEnumName(TypeInfo(T), Index); // $R-
end;

function GetDumpedTypeInfo(Root: PTypeInfo; Indent: RawByteString = ''): RawByteString;

   function GetTypeKindName(Kind: TTypeKind): RawByteString;
   begin
      case Kind of
       tkUnknown: Result := 'Unknown';
       tkInteger: Result := 'Integer';
       tkChar: Result := 'Char';
       tkEnumeration: Result := 'Enumeration';
       tkFloat: Result := 'Float';
       tkSet: Result := 'Set';
       tkMethod: Result := 'Method';
       tkSString: Result := 'Short String';
       tkLString: Result := 'LString';
       tkAString: Result := 'RawByteString';
       tkWString: Result := 'WideString';
       tkVariant: Result := 'Variant';
       tkArray: Result := 'Array';
       tkRecord: Result := 'Record';
       tkInterface: Result := 'Interface';
       tkClass: Result := 'Class';
       tkObject: Result := 'Object';
       tkWChar: Result := 'WideChar';
       tkBool: Result := 'Boolean';
       tkInt64: Result := 'Int64';
       tkQWord: Result := 'QWord';
       tkDynArray: Result := 'Dynamic Array';
       tkInterfaceRaw: Result := 'Raw Interface';
       tkProcVar: Result := 'Procedure Variable';
       tkUString: Result := 'UnicodeString';
       tkUChar: Result := 'UnicodeChar';
       tkHelper: Result := 'Helper';
       tkFile: Result := 'File';
       tkClassRef: Result := 'Class Reference';
       tkPointer: Result := 'Pointer';
      end;
   end;

   procedure AddStringField(const FieldName: RawByteString; var Result: RawByteString; const Value: ShortString);
   begin
      if (Value <> '') then
         Result := Result + Indent + FieldName + ': ' + Value + #10
      else
         Result := Result + Indent + FieldName + ': <unknown> ' + #10;
   end;

   procedure AddBooleanField(const FieldName: RawByteString; var Result: RawByteString; const Value: Boolean);
   begin
      if (Value) then
         Result := Result + Indent + FieldName + #10;
   end;

type
   PCallConv = ^TCallConv;
   PParamFlags = ^TParamFlags;
   PManagedField = ^TManagedField;

var
   Data: PTypeData;
   PropList: PPropList;
   ParamListData, ParamTypeData: Pointer;
   StringData, ResultType, ParamName, TypeName: PShortString;
   ResultTypeRef: PPTypeInfo;
   CCPtr: PCallConv;
   ParamFlagsPtr: PParamFlags;
   Index: LongInt;
   Count: SizeInt;
   ManagedField: PManagedField;
   ProcedureParam: PProcedureParam;
   PadString: ShortString;
begin
   if (not Assigned(Root)) then
   begin
      Result := '<nil>' + #10;
      exit;
   end;
   if (Root^.Name <> '') then
      Result := 'Type ' + Root^.Name + ' = ' + GetTypeKindName(Root^.Kind) + ':' + #10
   else
      Result := 'Anonymous ' + GetTypeKindName(Root^.Kind) + ' type:' + #10;
   Indent := Indent + '  ';
   Data := GetTypeData(Root);
   case Root^.Kind of
    tkUnKnown:
      Result := Result + Indent + '(unknown type)' + #10;
    tkLString,
    tkWString,
    tkUString:
      ; // nothing to say
    tkAString:
      Result := Result + Indent + 'Code page: ' + IntToStr(Data^.CodePage) + #10;
    tkVariant:
      ; // nothing to say
    tkInteger, tkChar, tkEnumeration, tkWChar, tkSet, tkBool:
      begin
        Result := Result + Indent + 'Ordinal type: ' + GetEnumName(TypeInfo(TOrdType), Ord(Data^.OrdType)) + #10;
        if (Root^.Kind = tkSet) then
        begin
           Result := Result + Indent + 'Composite type: ' + GetDumpedTypeInfo(Data^.CompType, Indent);
        end
        else
        begin
           Result := Result + Indent + 'Range: ' + IntToStr(Data^.MinValue) + '..' + IntToStr(Data^.MaxValue) + #10;
           if (Root^.Kind = tkEnumeration) then
           begin
              Result := Result + Indent + 'Name list: ' + Data^.NameList;
              StringData := GetNextShortString(@Data^.NameList);
              if (Data^.MaxValue > Data^.MinValue) then
                 for Index := Data^.MinValue+1 to Data^.MaxValue do // $R-
                 begin
                    Result := Result + ', ' + StringData^;
                    StringData := GetNextShortString(StringData);
                 end;
              Result := Result + #10;
              AddStringField('Unit name', Result, StringData^);
              Result := Result + Indent + 'Base type: ' + GetDumpedTypeInfo(Data^.BaseType, Indent);
           end;
        end;
     end;
    tkFloat:
      begin
        Result := Result + Indent + 'Float type: ' + GetEnumName(TypeInfo(TFloatType), Ord(Data^.FloatType)) + #10;
      end;
    tkSString:
      begin
        Result := Result + Indent + 'Maximum length: ' + IntToStr(Data^.MaxLength) + #10;
      end;
    tkClass:
      begin
        Result := Result + Indent + 'Class name: ' + Data^.ClassType.ClassName + #10;
        AddStringField('Unit name', Result, Data^.UnitName);
        Result := Result + Indent + 'Properties: (' + IntToStr(Data^.PropCount) + ')' + #10;
        Count := GetPropList(Root, PropList);
        if (Count > 0) then
           for Index := 0 to Count-1 do {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
           begin
              Result := Result + Indent + '  ' + PropList^[Index]^.Name + ': ' + GetDumpedTypeInfo(PropList^[Index]^.PropType, Indent + '  ');
              // XXX we could include further information about the property
           end;
        FreeMem(PropList);
        Result := Result + Indent + 'Parent class: ' + GetDumpedTypeInfo(Data^.ParentInfo, Indent);
      end;
    tkRecord:
      begin
        Result := Result + Indent + 'Record size: ' + IntToStr(Data^.RecSize) + ' bytes' + #10;
        Result := Result + Indent + 'Fields: (' + IntToStr(Data^.TotalFieldCount) + ')' + #10;
        ManagedField := AlignToPtr(Pointer(@Data^.TotalFieldCount) + SizeOf(Data^.TotalFieldCount));
        FillChar(PadString, SizeOf(PadString), ' '); {BOGUS Hint: Local variable "PadString" does not seem to be initialized}
        for Index := 1 to Data^.TotalFieldCount do
        begin
           Count := Length(IntToStr(ManagedField^.FldOffset));
           if (Count < 4) then
              SetLength(PadString, 4-Count)
           else
              SetLength(PadString, 0);
           Result := Result + Indent + '  +' + IntToStr(ManagedField^.FldOffset) + PadString + ' ' + GetDumpedTypeInfo(ManagedField^.TypeRef, Indent + '        ');
           ManagedField := AlignToPtr(Pointer(ManagedField) + SizeOf(TManagedField));
        end;
      end;
    tkHelper:
      begin
        AddStringField('Unit name', Result, Data^.UnitName);
        Result := Result + Indent + 'Properties: (' + IntToStr(Data^.PropCount) + ')' + #10;
        Result := Result + Indent + '  (properties not shown)' + #10;
        // XXX ...
        Result := Result + Indent + 'Helper parent: ' + GetDumpedTypeInfo(Data^.HelperParent, Indent);
        Result := Result + Indent + 'Helper extends: ' + GetDumpedTypeInfo(Data^.ExtendedInfo, Indent);
      end;
    tkMethod:
      begin
        Result := Result + Indent + 'Method kind: ' + GetEnumName(TypeInfo(TMethodKind), Ord(Data^.MethodKind)) + #10;

        // get pointers set up
        ParamListData := @Data^.ParamList;
        ParamTypeData := @Data^.ParamList;
        for Index := 1 to Data^.ParamCount do
        begin
           ParamTypeData := AlignToPtr(ParamTypeData + SizeOf(TParamFlags));
           ParamTypeData := AlignToPtr(ParamTypeData+Length(PShortString(ParamTypeData)^)+1);
           ParamTypeData := AlignToPtr(ParamTypeData+Length(PShortString(ParamTypeData)^)+1);
        end;
        if (Data^.MethodKind in [mkFunction, mkClassFunction]) then
        begin
           ResultType := PShortString(ParamTypeData);
           ParamTypeData := AlignToPtr(ParamTypeData + Length(PShortString(ParamTypeData)^)+1);
           ResultTypeRef := ParamTypeData;
           ParamTypeData := AlignToPtr(ParamTypeData + SizeOf(PTypeInfo));
        end;
        CCPtr := PCallConv(ParamTypeData);
        ParamTypeData := AlignToPtr(ParamTypeData + SizeOf(TCallConv));

        // output description in the order we want
        Result := Result + Indent + 'Calling convention: ' + GetEnumName(TypeInfo(TCallConv), Ord(CCPtr^)) + #10;
        Result := Result + Indent + 'Parameters: (' + IntToStr(Data^.ParamCount) + ')' + #10;
        for Index := 1 to Data^.ParamCount do
        begin
           ParamFlagsPtr := PParamFlags(ParamListData);
           ParamListData := AlignToPtr(ParamListData + SizeOf(TParamFlags));
           ParamName := PShortString(ParamListData);
           TypeName := GetNextShortString(ParamName);
           Result := Result + Indent + '  ' + ParamName^ + ': ' + TypeName^ + ' (Flags: ' + SetToString(PTypeInfo(TypeInfo(TParamFlags)), PByte(ParamFlagsPtr)^, True) + ')' + #10;
           Result := Result + Indent + '     ' + GetDumpedTypeInfo(PPTypeInfo(ParamTypeData)^, Indent + '     ');
           ParamListData := GetNextShortString(TypeName);
           ParamTypeData := AlignToPtr(ParamTypeData+SizeOf(PTypeInfo));
        end;
        if (Data^.MethodKind in [mkFunction, mkClassFunction]) then
           Result := Result + Indent + 'Result type: ' + ResultType^ + ' -- ' + GetDumpedTypeInfo(ResultTypeRef^, Indent);
      end;
    tkProcVar:
      begin
         Result := Result + Indent + 'Flags: ' + IntToStr(Data^.ProcSig.Flags) + #10;
         Result := Result + Indent + 'Calling convention: ' + GetEnumName(TypeInfo(TCallConv), Ord(Data^.ProcSig.CC)) + #10;

         Result := Result + Indent + 'Parameters: (' + IntToStr(Data^.ProcSig.ParamCount) + ')' + #10;
         if (Data^.ProcSig.ParamCount > 0) then
            for Index := 0 to Data^.ProcSig.ParamCount-1 do {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
            begin
               ProcedureParam := Data^.ProcSig.GetParam(Index);
               Result := Result + Indent + '  ' + ProcedureParam^.Name + ' (Flags: ' + SetToString(PTypeInfo(TypeInfo(TParamFlags)), PByte(@ProcedureParam^.ParamFlags)^, True) + '): ' + GetDumpedTypeInfo(ProcedureParam^.ParamType, Indent + '  ');
            end;
         Result := Result + Indent + 'Result type: ' + GetDumpedTypeInfo(Data^.ProcSig.ResultType, Indent);
      end;
    tkInt64:
      Result := Result + Indent + 'Range: ' + IntToStr(Data^.MinInt64Value) + '..' + IntToStr(Data^.MaxInt64Value) + #10;
    tkQWord:
      Result := Result + Indent + 'Range: ' + IntToStr(Data^.MinQWordValue) + '..' + IntToStr(Data^.MaxQWordValue) + #10;
    tkInterface:
      begin
         AddBooleanField('Is a Dual Dispatch interface', Result, ifDispInterface in Data^.IntfFlags);
         AddBooleanField('Is a Dispatch interface', Result, ifDispatch in Data^.IntfFlags);
         AddBooleanField('Has a GUID', Result, ifHasGuid in Data^.IntfFlags);
         AddBooleanField('Has a string GUID identifier', Result, ifHasStrGUID in Data^.IntfFlags);
         AddStringField('GUID', Result, '{' + IntToHex(Data^.GUID.Data1, 8) + '-' + IntToHex(Data^.GUID.Data2, 4) + '-' + IntToHex(Data^.GUID.Data3, 4) + '-' +
                                              IntToHex(Data^.GUID.Data4[0], 2) +
                                              IntToHex(Data^.GUID.Data4[1], 2) +
                                              IntToHex(Data^.GUID.Data4[2], 2) +
                                              IntToHex(Data^.GUID.Data4[3], 2) +
                                              IntToHex(Data^.GUID.Data4[4], 2) +
                                              IntToHex(Data^.GUID.Data4[5], 2) +
                                              IntToHex(Data^.GUID.Data4[6], 2) +
                                              IntToHex(Data^.GUID.Data4[7], 2) + '}');
         StringData := GetNextShortString(@Data^.RawIntfUnit);
         AddStringField('GUID string', Result, StringData^);
         AddStringField('Unit name', Result, Data^.IntfUnit);
         Result := Result + Indent + 'Parent interface2: ' + GetDumpedTypeInfo(Data^.IntfParent, Indent);
      end;
    tkInterfaceRaw:
      begin
         AddBooleanField('Is a Dispatch interface', Result, ifDispatch in Data^.RawIntfFlags);
         AddBooleanField('Is a Dual Dispatch interface', Result, ifDispInterface in Data^.RawIntfFlags);
         AddBooleanField('Has a GUID', Result, ifHasGuid in Data^.RawIntfFlags);
         AddBooleanField('Has a string GUID identifier', Result, ifHasStrGUID in Data^.RawIntfFlags);
         AddStringField('GUID', Result, '{' + IntToHex(Data^.IID.Data1, 8) + '-' + IntToHex(Data^.IID.Data2, 4) + '-' + IntToHex(Data^.IID.Data3, 4) + '-' +
                                              IntToHex(Data^.IID.Data4[0], 2) +
                                              IntToHex(Data^.IID.Data4[1], 2) +
                                              IntToHex(Data^.IID.Data4[2], 2) +
                                              IntToHex(Data^.IID.Data4[3], 2) +
                                              IntToHex(Data^.IID.Data4[4], 2) +
                                              IntToHex(Data^.IID.Data4[5], 2) +
                                              IntToHex(Data^.IID.Data4[6], 2) +
                                              IntToHex(Data^.IID.Data4[7], 2) + '}');
         StringData := GetNextShortString(@Data^.RawIntfUnit);
         AddStringField('GUID string', Result, StringData^);
         AddStringField('Unit name', Result, Data^.RawIntfUnit);
         Result := Result + Indent + 'Parent interface: ' + GetDumpedTypeInfo(Data^.RawIntfParent, Indent);
      end;
    tkArray:
      begin
         Result := Result + Indent + 'Size: ' + IntToStr(Data^.ArrayData.Size) + ' bytes' + #10;
         Result := Result + Indent + 'Element count: ' + IntToStr(Data^.ArrayData.ElCount) + #10;
         Result := Result + Indent + 'Dimensions: (' + IntToStr(Data^.ArrayData.DimCount) + ')' + #10;
         if (Data^.ArrayData.DimCount > 0) then
            for Index := 0 to Data^.ArrayData.DimCount-1 do // $R-
               Result := Result + Indent + '  ' + IntToStr(Index) + ': ' + GetDumpedTypeInfo(Data^.ArrayData.Dims[Index], Indent + '    '); // $R-
         Result := Result + Indent + 'Element type: ' + GetDumpedTypeInfo(Data^.ArrayData.ElType, Indent);
      end;
    tkDynArray:
      begin
         AddStringField('Unit name', Result, Data^.DynUnitName);
         Result := Result + Indent + 'Element size: ' + IntToStr(Data^.elSize) + ' bytes' + #10;
         Result := Result + Indent + 'Element type: ' + GetDumpedTypeInfo(Data^.elType, Indent);
         Result := Result + Indent + 'Element type two: ' + GetDumpedTypeInfo(Data^.elType2, Indent);
         Result := Result + Indent + 'Variable type: ' + IntToStr(Data^.varType) + #10;
      end;
    tkClassRef:
      Result := Result + Indent + 'Reference of ' + GetDumpedTypeInfo(Data^.InstanceType, Indent);
    tkPointer:
      Result := Result + Indent + 'Reference of ' + GetDumpedTypeInfo(Data^.InstanceType, Indent);
    else
      Result := Result + Indent + '(no further type information defined)' + #10;
   end;   
end;

generic function SetToStrings<T>(Values: T): TIdentifiers;
var
   SetInfo, EnumInfo: PTypeInfo;
   Index: Cardinal;
   ExpandedValues: TBytes;
begin
   SetInfo := TypeInfo(T);
   Assert(SetInfo^.Kind = tkSet, 'SetToString is only valid with sets');
   EnumInfo := GetTypeData(SetInfo)^.CompType;
   ExpandedValues := SetToArray(SetInfo, @Values);
   SetLength(Result, Length(ExpandedValues)); // {BOGUS Warning: Function result variable of a managed type does not seem to be initialized}
   if (Length(Result) > 0) then
   begin
      for Index := Low(ExpandedValues) to High(ExpandedValues) do // $R-
      begin
         Result[Index] := GetEnumName(EnumInfo, ExpandedValues[Index]);
      end;
   end;
end;

generic function SetToString<T>(Values: T): RawByteString;
begin
   Result := String.Join(', ', specialize SetToStrings<T>(Values));
end;

generic function EnumToString<T>(Value: T): RawByteString;
begin
   Str(Value, Result);
end;


{$DEFINE TESTS}

{$IFDEF TESTS}
procedure TestTypeDumper();
type
   TSet = set of (a, b, c);
begin
   Assert(GetDumpedTypeInfo(TypeInfo(TSet)) =
          'Type TSet = Set:'#10 +
          '  Ordinal type: otULong'#10 +
          '  Composite type: Anonymous Enumeration type:'#10 +
          '    Ordinal type: otULong'#10 +
          '    Range: 0..2'#10 +
          '    Name list: a, b, c'#10 +
          '    Unit name: typedump'#10 +
          '    Base type: <nil>'#10);
   Assert(GetDumpedTypeInfo(TypeInfo(True)) =
         'Type Boolean = Boolean:'#10 +
         '  Ordinal type: otUByte'#10 +
             '  Range: 0..1'#10);
   Assert(String.Join(', ', specialize SetToStrings<TSet>([c, a])) = 'a, c');
end;
{$ENDIF}

initialization
   {$IFDEF TESTS} TestTypeDumper(); {$ENDIF}
end.
