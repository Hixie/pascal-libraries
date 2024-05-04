{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit textstream;

interface

uses sysutils, unicode, hashtable, hashset, stringutils, typinfo;

type
   TTextStream = class;
   TClassLookup = function (ClassName: UTF8String): TClass;
   TCreator = reference to function (ClassType: TClass; Stream: TTextStream): TObject;

   TTextStream = class abstract
     public
      type
       TTokenKind = (tkNone, tkUnknown, tkIdentifier, tkPunctuation, tkString, tkEndOfFile);
     private
      type
       TObjectMemoryHashTable = specialize THashTable <UTF8String, TObject, UTF8StringUtils>;
      var
       FClassLookup: TClassLookup;
       FCreator: TCreator;
       FTokenKind: TTokenKind;
       FTokenSource: UTF8String;
       FLine, FColumn: Cardinal;
       FCurrentCharacter: TUnicodeCodepoint;
       FObjectMemory: TObjectMemoryHashTable;
       class function AlignToPtr(P: Pointer): Pointer; inline;
       class function GetNextShortString(const Current: PShortString): PShortString;
       generic function InternalGetEnum(EnumInfo: PTypeInfo): Integer;
     protected
      function DescribeCurrentToken(): UTF8String;
      procedure EnsureTokenReady();
      procedure AdvanceToken();
      function ReadCharacter(): TUnicodeCodepoint; virtual; abstract;
      procedure AdvanceCharacter();
      property CurrentCharacter: TUnicodeCodepoint read FCurrentCharacter;
      generic function GetObjectByName<T: TObject>(Name: UTF8String): T;
      generic procedure RememberObjectByName<T: TObject>(Target: T; Name: UTF8String);
     public
      constructor Create(AClassLookup: TClassLookup; ACreator: TCreator);
      destructor Destroy(); override;
      procedure Fail(Message: UTF8String);
      procedure FailExpected(Description: UTF8String);
      function PeekToken(): TTokenKind;
      // Identifiers
      function PeekIdentifier(): UTF8String;
      function GetIdentifier(): UTF8String;
      function GotIdentifier(Identifier: UTF8String): Boolean;
      procedure ExpectIdentifier(Identifier: UTF8String);
      // Punctuation
      function PeekPunctuation(): UTF8String;
      function GetPunctuation(): UTF8String;
      procedure ExpectPunctuation(Punctuation: UTF8String);
      // Objects
      function GetClass(): TClass;
      generic function GetObject<T: TObject>(): T;
      // Other primitive types
      function GetString(): UTF8String;
      function GetBoolean(): Boolean;
      generic function GetEnum<T>(): T;
      generic function GetSet<T>(): T; // T must be a set of T'
   end;

   TTextStreamFromString = class(TTextStream)
     private
      FData: UTF8String;
      FPosition: Cardinal;
     protected
      function ReadCharacter(): TUnicodeCodepoint; override;
     public
      constructor Create(Data: UTF8String; AClassLookup: TClassLookup; ACreator: TCreator);
   end;

   ETextStreamException = class(Exception)
    private
       FLine, FColumn: Cardinal;
    public
      constructor Create(AMessage: String; Line, Column: Cardinal);
      property Line: Cardinal read FLine;
      property Column: Cardinal read FColumn;
   end;

   TTextStreamProperties = class
    private    
     type
      TUTF8StringHashSet = specialize THashSet<UTF8String, UTF8StringUtils>;
     var
      FStream: TTextStream;
      FDone: Boolean;
      {$IFOPT C+} FActive: Boolean; {$ENDIF}
      FName: UTF8String;
      FPropertiesSeen: TUTF8StringHashSet;
    public
      constructor Create(Stream: TTextStream);
      destructor Destroy(); override;
      property Done: Boolean read FDone; // valid after calling Create or Advance, not after calling Accept
      property Name: UTF8String read FName; // valid when Done is True
      function Accept(): TTextStream; // valid after calling Create or Advance, when Done is False
      procedure Advance(); // valid after calling Accept
      function HandleUniqueStringProperty(PossibleName: UTF8String; var Value: UTF8String): Boolean;
      function HandleUniqueBooleanProperty(PossibleName: UTF8String; var Value: Boolean): Boolean;
      generic function HandleUniqueEnumProperty<T>(PossibleName: UTF8String; var Value: T): Boolean;
      generic function HandleUniqueClassProperty<T>(PossibleName: UTF8String; var Value: T; RequiredSuperclass: T): Boolean;
      procedure EnsureNotSeen(PropertyName: UTF8String);
      procedure EnsureSeen(Properties: array of UTF8String);
      function Seen(PropertyName: UTF8String): Boolean;
      procedure FailUnknownProperty();
      procedure Fail(Message: UTF8String);
   end;

implementation

uses
   exceptions, utf8, hashfunctions;

constructor TTextStream.Create(AClassLookup: TClassLookup; ACreator: TCreator);
begin
   Assert(Assigned(AClassLookup));
   Assert(Assigned(ACreator));
   FClassLookup := AClassLookup;
   FCreator := ACreator;
   Assert(FTokenKind = tkNone);
   Assert(FTokenSource = '');
   FLine := 1;
   FColumn := 0;
   AdvanceCharacter();
end;

destructor TTextStream.Destroy();
begin
   if (Assigned(FObjectMemory)) then
      FObjectMemory.Free();
   inherited Destroy();
end;

procedure TTextStream.Fail(Message: UTF8String);
begin
   raise ETextStreamException.Create(Message, FLine, FColumn);
end;

procedure TTextStream.FailExpected(Description: UTF8String);
begin
   raise ETextStreamException.Create('Expected ' + Description + ', but got ' + DescribeCurrentToken() + '.', FLine, FColumn);
end;

function TTextStream.DescribeCurrentToken(): UTF8String;
begin
   case (FTokenKind) of
      tkNone: Result := 'nothing';
      tkUnknown: Result := 'inexplicable character "' + FTokenSource + '"';
      tkIdentifier: Result := 'identifier "' + FTokenSource + '"';
      tkPunctuation: Result := 'symbol "' + FTokenSource + '"';
      tkString: Result := 'quoted string "' + FTokenSource + '"';
      tkEndOfFile: Result := 'the end of the stream';
   end;
end;

procedure TTextStream.EnsureTokenReady();

   function IsWhitespace(Character: TUnicodeCodepoint): Boolean;
   begin
      case (Character.Value) of
         $0020, $000A, $000D, $0009:
            Result := True;
      else
         Result := False;
      end;
   end;

   function IsAlphanumeric(Character: TUnicodeCodepoint): Boolean;
   begin
      case (Character.Value) of
         $0030..$0039, $0041..$005A, $0061..$007A, $005F: Result := True;
      else
         Result := False;
      end;
   end;

   // XXX the following two procedures really should avoid all the copying
   // of the string and just track the substring indices then copy once
   
   procedure ReadIdentifier();
   var
      Identifier: TUnicodeCodepointArray;
      ActualLength: Cardinal;
   begin
      ActualLength := 1;
      SetLength(Identifier, 10); // $DFA- for Identifier
      Identifier[ActualLength - 1] := CurrentCharacter;
      AdvanceCharacter();
      while (IsAlphanumeric(CurrentCharacter)) do
      begin
         if (ActualLength >= Length(Identifier)) then
            SetLength(Identifier, Length(Identifier) * 2);
         Identifier[ActualLength] := CurrentCharacter;
         Inc(ActualLength);
         AdvanceCharacter();
      end;
      SetLength(Identifier, ActualLength);
      FTokenSource := CodepointArrayToUTF8String(Identifier);
      FTokenKind := tkIdentifier;
   end;

   procedure ReadString();
   var
      QuotedString: TUnicodeCodepointArray;
      ActualLength: Cardinal;
   begin
      ActualLength := 0;
      SetLength(QuotedString, 10); // $DFA- for QuotedString
      AdvanceCharacter();
      while ((CurrentCharacter <> kEOF) and (CurrentCharacter <> $0022)) do
      begin
         if (ActualLength >= Length(QuotedString)) then
            SetLength(QuotedString, Length(QuotedString) * 2);
         QuotedString[ActualLength] := CurrentCharacter;
         Inc(ActualLength);
         AdvanceCharacter();
      end;
      if (CurrentCharacter = kEOF) then
         Fail('Unterminated quoted string');
      AdvanceCharacter();
      SetLength(QuotedString, ActualLength);
      FTokenSource := CodepointArrayToUTF8String(QuotedString);
      FTokenKind := tkString;
   end;

   procedure Save(TokenKind: TTokenKind; TokenSource: UTF8String);
   begin
      FTokenKind := TokenKind;
      FTokenSource := TokenSource;
   end;
   
begin
   if (FTokenKind <> tkNone) then
      Exit;
   Assert(FTokenSource = '');
   while (IsWhitespace(CurrentCharacter)) do
      AdvanceCharacter();
   case (CurrentCharacter.Value) of
      {$IFOPT C+} kNone: Assert(False, 'Failed to read character.'); {$ENDIF}
      kEOF: Save(tkEndOfFile, '<EOF>');
      $0041..$005A, $0061..$007A:
         ReadIdentifier();
      $0021, $0023..$002F, $003A..$0040, $005B..$0060, $007B..$007E:
         begin
            Save(tkPunctuation, CodepointToUTF8(CurrentCharacter));
            AdvanceCharacter();
         end;
      $0022:
         ReadString();
      else
         Save(tkUnknown, CodepointToUTF8(CurrentCharacter));
   end;
end;

procedure TTextStream.AdvanceToken();
begin
   FTokenKind := tkNone;
   FTokenSource := '';
end;

procedure TTextStream.AdvanceCharacter();
begin
   FCurrentCharacter := ReadCharacter();
   if (FCurrentCharacter = $000A) then
   begin
      Inc(FLine);
      FColumn := 0;
   end
   else
   begin
      Inc(FColumn);
   end;
end;

function TTextStream.PeekToken(): TTokenKind;
begin
   EnsureTokenReady();
   Result := FTokenKind;
end;

function TTextStream.PeekIdentifier(): UTF8String;
begin
   EnsureTokenReady();
   if (FTokenKind = tkIdentifier) then
      Result := FTokenSource
   else
      Result := '';
end;

function TTextStream.GetIdentifier(): UTF8String;
begin
   EnsureTokenReady();
   if (FTokenKind <> tkIdentifier) then
      FailExpected('identifier');
   Result := FTokenSource;
   AdvanceToken();
end;

function TTextStream.GotIdentifier(Identifier: UTF8String): Boolean;
begin
   Result := PeekIdentifier() = Identifier;
   if (Result) then
      AdvanceToken();
end;

procedure TTextStream.ExpectIdentifier(Identifier: UTF8String);
var
   ActualIdentifier: UTF8String;
begin
   ActualIdentifier := GetIdentifier();
   if (ActualIdentifier <> Identifier) then
      FailExpected('"' + Identifier + '"');
end;

function TTextStream.PeekPunctuation(): UTF8String;
begin
   EnsureTokenReady();
   if (FTokenKind = tkPunctuation) then
      Result := FTokenSource
   else
      Result := '';
end;

function TTextStream.GetPunctuation(): UTF8String;
begin
   EnsureTokenReady();
   if (FTokenKind <> tkPunctuation) then
      FailExpected('punctuation');
   Result := FTokenSource;
   AdvanceToken();
end;

procedure TTextStream.ExpectPunctuation(Punctuation: UTF8String);
var
   ActualPunctuation: UTF8String;
begin
   ActualPunctuation := GetPunctuation();
   if (ActualPunctuation <> Punctuation) then
      FailExpected('"' + Punctuation + '"');
end;

function TTextStream.GetClass(): TClass;
begin
   Result := FClassLookup(GetIdentifier());
end;

generic function TTextStream.GetObject<T>(): T;
var
   SpecifiedClass: TClass;
   CreatedObject: TObject;
   Name: UTF8String;
begin
   if (GotIdentifier('new')) then
   begin
      SpecifiedClass := GetClass();
      if ((SpecifiedClass <> T) and (not SpecifiedClass.InheritsFrom(T))) then
         Fail('Expected subclass of ' + T.ClassName); // XXX list the available options
      if (GotIdentifier('named')) then
      begin
         Name := GetIdentifier();
      end
      else
      begin  
         Name := '';
      end;
      ExpectPunctuation('{');
      Assert(Assigned(FCreator));
      CreatedObject := FCreator(SpecifiedClass, Self);
      Assert(Assigned(CreatedObject));
      Assert((CreatedObject.ClassType = T) or (CreatedObject.ClassType.InheritsFrom(T)));
      Result := T(CreatedObject);
      ExpectPunctuation('}');
      if (Name <> '') then
      begin
         try
            specialize RememberObjectByName<T>(Result, Name);
         except
            Result.Free();
         end;
      end;
   end
   else
   begin
      Name := GetIdentifier();
      Result := specialize GetObjectByName<T>(Name);
      if (not Assigned(Result)) then
         Fail('No previously-created object is named "' + Name + '". Use "new" to create a new object.');
   end;
end;

generic function TTextStream.GetObjectByName<T>(Name: UTF8String): T;
begin
   if (Assigned(FObjectMemory)) then
   begin
      Result := FObjectMemory[Name] as T;
   end
   else
      Result := nil;
end;

generic procedure TTextStream.RememberObjectByName<T>(Target: T; Name: UTF8String);
begin
   if (not Assigned(FObjectMemory)) then
   begin
      FObjectMemory := TObjectMemoryHashTable.Create(@UTF8StringHash32);
   end;
   if (FObjectMemory.Has(Name)) then
      Fail('Name "' + name + '" registered multiple times.');
   FObjectMemory.Add(Name, Target);
end;

function TTextStream.GetString(): UTF8String;
begin
   EnsureTokenReady();
   if (FTokenKind <> tkString) then
      FailExpected('string');
   Result := FTokenSource;
   AdvanceToken();
end;

class function TTextStream.AlignToPtr(P: Pointer): Pointer; inline;
begin
   {$IFDEF FPC_REQUIRES_PROPER_ALIGNMENT}
     Result := Align(P,SizeOf(P));
   {$ELSE FPC_REQUIRES_PROPER_ALIGNMENT}
     Result := P;
   {$ENDIF FPC_REQUIRES_PROPER_ALIGNMENT}
end;

class function TTextStream.GetNextShortString(const Current: PShortString): PShortString;
begin
   Result := PShortString(AlignToPtr(Pointer(Current)+Length(Current^)+1));
end;

generic function TTextStream.InternalGetEnum(EnumInfo: PTypeInfo): Integer;
var
   Name: UTF8String;
   AllowedNames: UTF8String;
   TypeData: PTypeData;
   StringData: PShortString;
   Index: Cardinal;
begin
   Assert(EnumInfo^.Kind = tkEnumeration);
   Name := GetIdentifier();
   Result := GetEnumValue(EnumInfo, Name);
   if (Result < 0) then
   begin
      TypeData := GetTypeData(EnumInfo);
      StringData := @TypeData^.NameList;
      AllowedNames := StringData^; // first name
      if (TypeData^.MaxValue > TypeData^.MinValue) then
      begin
         for Index := TypeData^.MinValue+1 to TypeData^.MaxValue do // $R-
         begin
            StringData := GetNextShortString(StringData);
            AllowedNames := AllowedNames + ', ' + StringData^;
         end;
      end;
      Fail('Unrecognized value "' + Name + '"; valid values are: ' + AllowedNames);
   end;
end;

generic function TTextStream.GetEnum<T>(): T;
begin
   Result := T(InternalGetEnum(TypeInfo(T)));
end;

generic function TTextStream.GetSet<T>(): T;
var
   SetInfo, EnumInfo: PTypeInfo;
   Composite, Bit: Cardinal;
   Value: Integer;
begin
   SetInfo := TypeInfo(T);
   Assert(SetInfo^.Kind = tkSet);
   EnumInfo := GetTypeData(SetInfo)^.CompType;
   Assert(GetTypeData(EnumInfo)^.OrdType = GetTypeData(TypeInfo(Cardinal))^.OrdType);
   Composite := 0;
   while (PeekToken() = tkIdentifier) do
   begin
      Value := InternalGetEnum(EnumInfo);
      Assert(Value < SizeOf(Cardinal) * 8);
      Bit := 1 << Value; // $R- (asserted on previous line)
      if (Composite and Bit > 0) then
         Fail('Duplicate value in set');
      Composite += Bit; // $R- (verified by preceding conditional)
   end;
   Result := T(Composite);
end;

function TTextStream.GetBoolean(): Boolean;
var
   Identifier: UTF8String;
begin
   Identifier := GetIdentifier();
   if (Identifier = 'true') then
      Result := True
   else
   if (Identifier = 'false') then
      Result := False
   else
      FailExpected('boolean');
end;


constructor TTextStreamFromString.Create(Data: UTF8String; AClassLookup: TClassLookup; ACreator: TCreator);
begin
   FData := Data;
   FPosition := 1;
   {$IFOPT C+} FCurrentCharacter := kNone; {$ENDIF}
   inherited Create(AClassLookup, ACreator);
end;

function TTextStreamFromString.ReadCharacter(): TUnicodeCodepoint;
var
   BytesRead: TUTF8SequenceLength;
begin
   if (FPosition > Length(FData)) then
   begin
      Result := kEOF;
   end
   else
   begin
      Result := UTF8ToCodepoint(@FData, FPosition, BytesRead);
      Inc(FPosition, BytesRead); // $DFA- for BytesRead
   end;
end;

constructor ETextStreamException.Create(AMessage: String; Line, Column: Cardinal);
begin
   inherited Create(AMessage);
   FLine := Line;
   FColumn := Column;
end;

constructor TTextStreamProperties.Create(Stream: TTextStream);
begin
   FPropertiesSeen := TUTF8StringHashSet.Create(@UTF8StringHash32, 8);
   FStream := Stream;
   Advance();
end;

destructor TTextStreamProperties.Destroy();
begin
   FPropertiesSeen.Free();
   inherited;
end;

function TTextStreamProperties.Accept(): TTextStream;
begin
   Assert(not FDone, 'Tried to accept property after properties were finished.');
   Assert(FName <> '', 'Tried to accept property before advancing into one.');
   {$IFOPT C+} FActive := True; {$ENDIF}
   if (not FPropertiesSeen.Has(FName)) then
      FPropertiesSeen.Add(FName);
   Result := FStream;
end;

procedure TTextStreamProperties.Advance();
begin
   Assert(not FDone);
   {$IFOPT C+} Assert((FName = '') xor FActive); {$ENDIF}
   if (FName <> '') then
      FStream.ExpectPunctuation(';');
   if (FStream.PeekPunctuation() <> '}') then
   begin
      {$IFOPT C+} FActive := False; {$ENDIF}
      FName := FStream.GetIdentifier();
      Assert(FName <> '');
      FStream.ExpectPunctuation(':');
   end
   else
   begin
      FDone := True;
   end;
end;

function TTextStreamProperties.HandleUniqueStringProperty(PossibleName: UTF8String; var Value: UTF8String): Boolean;
begin
   if (Name = PossibleName) then
   begin
      EnsureNotSeen(PossibleName);
      Value := Accept().GetString();
      Advance();
      Result := False;
   end
   else
      Result := True;
end;

function TTextStreamProperties.HandleUniqueBooleanProperty(PossibleName: UTF8String; var Value: Boolean): Boolean;
begin
   if (Name = PossibleName) then
   begin
      EnsureNotSeen(PossibleName);
      Value := Accept().GetBoolean();
      Advance();
      Result := False;
   end
   else
      Result := True;
end;

generic function TTextStreamProperties.HandleUniqueClassProperty<T>(PossibleName: UTF8String; var Value: T; RequiredSuperclass: T): Boolean;
var
   Candidate: TClass;
begin
   if (Name = PossibleName) then
   begin
      EnsureNotSeen(PossibleName);
      Candidate := Accept().GetClass();
      if (not Assigned(Candidate)) then
         Fail('Class specified for "' + PossibleName + '" not recognized');
      if (not ((Candidate = RequiredSuperclass) or (Candidate.InheritsFrom(RequiredSuperclass)))) then
         Fail('Class specified for "' + PossibleName + '" is not acceptable, must be a ' + RequiredSuperclass.ClassName);
      Value := T(Candidate);
      Advance();
      Result := False;
   end
   else
      Result := True;
end;

generic function TTextStreamProperties.HandleUniqueEnumProperty<T>(PossibleName: UTF8String; var Value: T): Boolean;
begin
   if (Name = PossibleName) then
   begin
      EnsureNotSeen(PossibleName);
      Value := Accept().specialize GetEnum<T>();
      Advance();
      Result := False;
   end
   else
      Result := True;
end;

procedure TTextStreamProperties.EnsureNotSeen(PropertyName: UTF8String);
begin
   if (FPropertiesSeen.Has(PropertyName)) then
      Fail('Property "' + PropertyName + '" can only be specified once');
end;

procedure TTextStreamProperties.EnsureSeen(Properties: array of UTF8String);
var
   WantedName: UTF8String;
begin
   for WantedName in Properties do
   begin
      if (not FPropertiesSeen.Has(WantedName)) then
         Fail('Required property "' + WantedName + '" not found');
   end;      
end;

function TTextStreamProperties.Seen(PropertyName: UTF8String): Boolean;
begin
   Result := FPropertiesSeen.Has(PropertyName);
end;
   
procedure TTextStreamProperties.FailUnknownProperty();
begin
   Fail('Unknown property "' + FName + '"');
end;

procedure TTextStreamProperties.Fail(Message: UTF8String);
begin
   FStream.Fail(Message);
end;

end.
