{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit rtlutils;

interface

function GetRefCount(constref S: UTF8String): SizeInt; inline;
procedure IncRefCount(var S: UTF8String); inline;
procedure DecRefCount(var S: UTF8String); inline;

{$IFOPT C+} procedure AssertStringIsConstant(constref S: UTF8String); {$ENDIF}
{$IFOPT C+} procedure AssertStringIsReffed(constref S: UTF8String; const MinRef: Cardinal); {$ENDIF}

implementation

type
   PAnsiRec = ^TAnsiRec;
   TAnsiRec = record
      // based on TAnsiRec in astrings.inc
      CodePage: TSystemCodePage;
      ElementSize: Word;
      {$IF NOT DEFINED(VER3_2)}
        {$IFDEF CPU64}
          RefCount: Longint;
        {$ELSE}
          RefCount: SizeInt;
        {$ENDIF}
      {$ELSE}
        {$IFDEF CPU64}
          Dummy: DWord;
        {$ENDIF CPU64}
          RefCount: SizeInt;
      {$ENDIF}
      Length: SizeInt;
      Data: record end;
   end;

function GetRefCount(constref S: UTF8String): SizeInt;
var
   StringStart: PAnsiRec;
begin
   if (S <> '') then
   begin
      StringStart := PAnsiRec(Pointer(S)-SizeOf(TAnsiRec));
      Result := StringStart^.RefCount;
   end
   else
      Result := 1;
end;

procedure IncRefCount(var S: UTF8String);
var
   StringStart: PAnsiRec;
begin
   if (S <> '') then
   begin
      StringStart := PAnsiRec(Pointer(S)-SizeOf(TAnsiRec));
      if (StringStart^.RefCount <> -1) then
      begin
         Inc(StringStart^.RefCount);
      end;
   end;
end;

procedure DecRefCount(var S: UTF8String);
var
   StringStart: PAnsiRec;
begin
   if (S <> '') then
   begin
      StringStart := PAnsiRec(Pointer(S)-SizeOf(TAnsiRec));
      if (StringStart^.RefCount <> -1) then
      begin
         Dec(StringStart^.RefCount);
      end;
   end;
end;

{$IFOPT C+}
procedure AssertStringIsConstant(constref S: UTF8String);
var
   StringStart: PAnsiRec;
begin
   if (S <> '') then
   begin
      StringStart := PAnsiRec(Pointer(S)-SizeOf(TAnsiRec));
      Assert(StringStart^.RefCount = -1);
   end;
end;
{$ENDIF}

{$IFOPT C+}
procedure AssertStringIsReffed(constref S: UTF8String; const MinRef: Cardinal);
var
   StringStart: PAnsiRec;
begin
   if (S <> '') then
   begin
      StringStart := PAnsiRec(Pointer(S)-SizeOf(TAnsiRec));
      Assert(StringStart^.RefCount >= MinRef);
   end;
end;
{$ENDIF}

initialization
   {$IFOPT C+}
   AssertStringIsConstant('rtlutils.pas test');
   {$ENDIF}
end.