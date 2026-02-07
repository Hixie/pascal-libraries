{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit genericutils;

interface

type
   generic DefaultUtils <T> = record
      class function Equals(const A, B: T): Boolean; static; inline;
      class function LessThan(const A, B: T): Boolean; static; inline;
      class function GreaterThan(const A, B: T): Boolean; static; inline;
      class function Compare(const A, B: T): Int64; static; inline;
   end;

   generic DefaultNumericUtils <T> = record
      class function Equals(const A, B: T): Boolean; static; inline;
      class function LessThan(const A, B: T): Boolean; static; inline;
      class function GreaterThan(const A, B: T): Boolean; static; inline;
      class function Compare(const A, B: T): Int64; static; inline;
   end;

   generic DefaultUnorderedUtils <T> = record
      class function Equals(const A, B: T): Boolean; static; inline;
      class function LessThan(const A, B: T): Boolean; static; inline;
      class function GreaterThan(const A, B: T): Boolean; static; inline;
      class function Compare(const A, B: T): Int64; static; inline;
   end;

   generic IncomparableUtils <T> = record
      class function Equals(const A, B: T): Boolean; static; inline;
      class function LessThan(const A, B: T): Boolean; static; inline;
      class function GreaterThan(const A, B: T): Boolean; static; inline;
      class function Compare(const A, B: T): Int64; static; inline;
   end;

   TObjectUtils = specialize DefaultUnorderedUtils <TObject>;
   WordUtils = specialize DefaultNumericUtils <Word>;
   CardinalUtils = specialize DefaultNumericUtils <Cardinal>;
   LongIntUtils = specialize DefaultNumericUtils <LongInt>;
   IntegerUtils = specialize DefaultNumericUtils <Integer>;
   PointerUtils = specialize DefaultNumericUtils <Pointer>;
   PtrUIntUtils = specialize DefaultNumericUtils <PtrUInt>;
   DoubleUtils = specialize DefaultUtils <Double>;
   RawByteStringUtils = specialize DefaultUtils <RawByteString>;
   // for UTF8StringUtils, see stringutils.pas

implementation

uses
   sysutils;

class function DefaultUtils.Equals(const A, B: T): Boolean;
begin
   Result := A = B;
end;

class function DefaultUtils.LessThan(const A, B: T): Boolean;
begin
   Result := A < B;
end;

class function DefaultUtils.GreaterThan(const A, B: T): Boolean;
begin
   Result := A > B;
end;

class function DefaultUtils.Compare(const A, B: T): Int64;
begin
   if (A < B) then
      Result := -1
   else
   if (A > B) then
      Result := 1
   else
      Result := 0;
end;


class function DefaultNumericUtils.Equals(const A, B: T): Boolean;
begin
   Result := A = B;
end;

class function DefaultNumericUtils.LessThan(const A, B: T): Boolean;
begin
   Result := A < B;
end;

class function DefaultNumericUtils.GreaterThan(const A, B: T): Boolean;
begin
   Result := A > B;
end;

class function DefaultNumericUtils.Compare(const A, B: T): Int64;
begin
   {$PUSH}
   {$POINTERMATH ON}
   Result := A - B; // $R-
   {$POP}
end;


class function DefaultUnorderedUtils.Equals(const A, B: T): Boolean;
begin
   Result := A = B;
end;

class function DefaultUnorderedUtils.LessThan(const A, B: T): Boolean;
begin
   raise Exception.Create('tried to compare unordered data');
   Result := False;
end;

class function DefaultUnorderedUtils.GreaterThan(const A, B: T): Boolean;
begin
   raise Exception.Create('tried to compare unordered data');
   Result := False;
end;

class function DefaultUnorderedUtils.Compare(const A, B: T): Int64;
begin
   raise Exception.Create('tried to compare unordered data');
   Result := 0;
end;


class function IncomparableUtils.Equals(const A, B: T): Boolean;
begin
   Result := False;
end;

class function IncomparableUtils.LessThan(const A, B: T): Boolean;
begin
   raise Exception.Create('tried to compare unordered data');
   Result := False;
end;

class function IncomparableUtils.GreaterThan(const A, B: T): Boolean;
begin
   raise Exception.Create('tried to compare unordered data');
   Result := False;
end;

class function IncomparableUtils.Compare(const A, B: T): Int64;
begin
   raise Exception.Create('tried to compare unordered data');
   Result := 0;
end;

end.
