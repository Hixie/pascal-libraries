{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit intutils;

interface

{$DEFINE TESTS}

function ParseUInt64(const Value: UTF8String; Default: UInt64 = 0): UInt64;
function ParseUInt32(const Value: UTF8String; Default: UInt32 = 0): UInt32;
function ParseInt64(const Value: UTF8String; Default: Int64 = 0): Int64;
function ParseInt32(const Value: UTF8String; Default: Int32 = 0): Int32;

// Reads an integer, returns how many bytes were parsed. Parsed integer is Output.
// Output is undefined if return value is zero.
// Will not read more than MaxLength bytes from Value.
function ParseUInt64(Value: PByte; MaxLength: Cardinal; out Output: UInt64): Cardinal;
function ParseUInt32(Value: PByte; MaxLength: Cardinal; out Output: UInt32): Cardinal;
function ParseInt64(Value: PByte; MaxLength: Cardinal; out Output: Int64): Cardinal;
function ParseInt32(Value: PByte; MaxLength: Cardinal; out Output: Int32): Cardinal;

implementation

function ParseUInt64(Value: PByte; MaxLength: Cardinal; out Output: UInt64): Cardinal;
var
   BufferEnd: PByte;
   Current: PByte;
   Temp: UInt64;
begin
   Current := Value;
   BufferEnd := Value + MaxLength;
   if ((Current >= BufferEnd) or (Current^ < $30) or (Current^ > $39)) then
   begin
      Result := 0;
      exit;
   end;
   Output := 0;
   repeat
      {$PUSH}
      {$OVERFLOWCHECKS-}
      {$RANGECHECKS-}
      Temp := Output * 10 + (Current^ - $30); // $R-
      if (Temp < Output) then
      begin
         Result := 0;
         exit;
      end;
      Output := Temp;
      Inc(Current);
      {$POP}
   until ((Current >= BufferEnd) or (Current^ < $30) or (Current^ > $39));
   Assert(Current > Value);
   Result := Current - Value; // $R-
end;

function ParseUInt32(Value: PByte; MaxLength: Cardinal; out Output: UInt32): Cardinal;
var
   Temp: UInt64;
begin
   Result := ParseUInt64(Value, MaxLength, Temp);
   if (Result > 0) then
   begin
      if (Temp > High(UInt32)) then
      begin
         Result := 0;
      end
      else
      begin
         Output := Temp; // $R-
      end;
   end;
end;

function ParseInt64(Value: PByte; MaxLength: Cardinal; out Output: Int64): Cardinal;
var
   Unsigned: UInt64;
begin
   Result := 0;
   if (MaxLength = 0) then
      exit;
   if (Value^ = $2D) then
   begin
      Result := ParseUInt64(Value + 1, MaxLength - 1, Unsigned); // $R-
      if (Result = 0) then
         exit;
      if (Unsigned > UInt64(-Low(Int64))) then
      begin
         Result := 0;
         exit;
      end;
      Inc(Result);
      if (Unsigned = UInt64(-Low(Int64))) then
      begin
         Output := Low(Int64);
         exit;
      end;
      Output := -Unsigned; // $R-
      exit;
   end
   else
   begin
      Result := ParseUInt64(Value, MaxLength, Unsigned);
      if (Result = 0) then
         exit;
      if (Unsigned > UInt64(High(Int64))) then
      begin
         Result := 0;
         exit;
      end;
      Output := Unsigned; // $R-
   end;
end;

function ParseInt32(Value: PByte; MaxLength: Cardinal; out Output: Int32): Cardinal;
var
   Unsigned: UInt64;
begin
   Result := 0;
   if (MaxLength = 0) then
      exit;
   if (Value^ = $2D) then
   begin
      Result := ParseUInt64(Value + 1, MaxLength - 1, Unsigned); // $R-
      if (Result = 0) then
         exit;
      if (Unsigned > UInt64(-Low(Int32))) then
      begin
         Result := 0;
         exit;
      end;
      Inc(Result);
      if (Unsigned = UInt64(-Low(Int32))) then
      begin
         Output := Low(Int32);
         exit;
      end;
      Output := -Unsigned; // $R-
      exit;
   end
   else
   begin
      Result := ParseUInt64(Value, MaxLength, Unsigned);
      if (Result = 0) then
         exit;
      if (Unsigned > UInt64(High(Int32))) then
      begin
         Result := 0;
         exit;
      end;
      Output := Unsigned; // $R-
   end;
end;

function ParseUInt64(const Value: UTF8String; Default: UInt64 = 0): UInt64;
begin
   if (Value = '') then
   begin
      Result := Default;
   end
   else
   if (ParseUInt64(PByte(@Value[1]), Length(Value), Result) <> Length(Value)) then // $R-
   begin
      Result := Default;
   end;
end;

function ParseUInt32(const Value: UTF8String; Default: UInt32 = 0): UInt32;
var
   Temp: UInt64;
begin
   if (Value = '') then
   begin
      Result := Default;
   end
   else
   if ((ParseUInt64(PByte(@Value[1]), Length(Value), Temp) <> Length(Value)) or // $R-
       (Temp > High(UInt32))) then
   begin
      Result := Default;
   end
   else
   begin
      Result := Temp; // $R-
   end;
end;

function ParseInt64(const Value: UTF8String; Default: Int64 = 0): Int64;
begin
   if (Value = '') then
   begin
      Result := Default;
   end
   else
   if (ParseInt64(PByte(@Value[1]), Length(Value), Result) <> Length(Value)) then // $R-
   begin
      Result := Default;
   end;
end;

function ParseInt32(const Value: UTF8String; Default: Int32 = 0): Int32;
begin
   if (Value = '') then
   begin
      Result := Default;
   end
   else
   if (ParseInt32(PByte(@Value[1]), Length(Value), Result) <> Length(Value)) then // $R-
   begin
      Result := Default;
   end;
end;

{$IFDEF TESTS}
procedure TestParseUInt64();
var
   ParsedUInt64: UInt64;
   ParsedLength: Cardinal;
   Buffer: UTF8String;
begin
   Buffer := '123';
   ParsedLength := ParseUInt64(PByte(@Buffer[1]), Length(Buffer), ParsedUInt64); // $R-
   Assert(ParsedLength = 3);
   Assert(ParsedUInt64 = 123);

   ParsedLength := ParseUInt64(PByte(0), 0, ParsedUInt64); // $R-
   Assert(ParsedLength = 0);

   Buffer := '-123'; // negative (leading garbage)
   ParsedLength := ParseUInt64(PByte(@Buffer[1]), Length(Buffer), ParsedUInt64); // $R-
   Assert(ParsedLength = 0);

   Buffer := '12a3'; // trailing garbage
   ParsedLength := ParseUInt64(PByte(@Buffer[1]), Length(Buffer), ParsedUInt64); // $R-
   Assert(ParsedLength = 2);
   Assert(ParsedUInt64 = 12);

   Buffer := '12345678901234567890123456789012345678901234567890'; // much too long
   ParsedLength := ParseUInt64(PByte(@Buffer[1]), Length(Buffer), ParsedUInt64); // $R-
   Assert(ParsedLength = 0);

   Buffer := '18446744073709551620'; // overflow on multiplication
   ParsedLength := ParseUInt64(PByte(@Buffer[1]), Length(Buffer), ParsedUInt64); // $R-
   Assert(ParsedLength = 0);

   Buffer := '18446744073709551616'; // overflow on addition
   ParsedLength := ParseUInt64(PByte(@Buffer[1]), Length(Buffer), ParsedUInt64); // $R-
   Assert(ParsedLength = 0);

   Buffer := '18446744073709551615'; // max
   ParsedLength := ParseUInt64(PByte(@Buffer[1]), Length(Buffer), ParsedUInt64); // $R-
   Assert(ParsedLength = Length(Buffer));
   Assert(ParsedUInt64 = 18446744073709551615);

   Buffer := '00000000000000000000000000000000000000000000000000';
   ParsedLength := ParseUInt64(PByte(@Buffer[1]), Length(Buffer), ParsedUInt64); // $R-
   Assert(ParsedLength = Length(Buffer));
   Assert(ParsedUInt64 = 0);
end;

procedure TestParseInt64();
var
   ParsedInt64: Int64;
   ParsedLength: Cardinal;
   Buffer: UTF8String;
begin
   Buffer := '123';
   ParsedLength := ParseInt64(PByte(@Buffer[1]), Length(Buffer), ParsedInt64); // $R-
   Assert(ParsedLength = 3);
   Assert(ParsedInt64 = 123);

   ParsedLength := ParseInt64(PByte(0), 0, ParsedInt64); // $R-
   Assert(ParsedLength = 0);

   Buffer := '-123'; // negative
   ParsedLength := ParseInt64(PByte(@Buffer[1]), Length(Buffer), ParsedInt64); // $R-
   Assert(ParsedLength = 4);
   Assert(ParsedInt64 = -123);

   Buffer := '--123'; // leading garbage
   ParsedLength := ParseInt64(PByte(@Buffer[1]), Length(Buffer), ParsedInt64); // $R-
   Assert(ParsedLength = 0);

   Buffer := '-0';
   ParsedLength := ParseInt64(PByte(@Buffer[1]), Length(Buffer), ParsedInt64); // $R-
   Assert(ParsedLength = 2);
   Assert(ParsedInt64 = 0);

   Buffer := '12a3'; // trailing garbage
   ParsedLength := ParseInt64(PByte(@Buffer[1]), Length(Buffer), ParsedInt64); // $R-
   Assert(ParsedLength = 2);
   Assert(ParsedInt64 = 12);

   Buffer := '12345678901234567890123456789012345678901234567890'; // much too long
   ParsedLength := ParseInt64(PByte(@Buffer[1]), Length(Buffer), ParsedInt64); // $R-
   Assert(ParsedLength = 0);

   Buffer := '18446744073709551620'; // overflow on multiplication
   ParsedLength := ParseInt64(PByte(@Buffer[1]), Length(Buffer), ParsedInt64); // $R-
   Assert(ParsedLength = 0);

   Buffer := '18446744073709551616'; // overflow on addition
   ParsedLength := ParseInt64(PByte(@Buffer[1]), Length(Buffer), ParsedInt64); // $R-
   Assert(ParsedLength = 0);

   Buffer := '18446744073709551615'; // overflow on conversion to signed
   ParsedLength := ParseInt64(PByte(@Buffer[1]), Length(Buffer), ParsedInt64); // $R-
   Assert(ParsedLength = 0);

   Buffer := '9223372036854775808'; // overflow on conversion to signed
   ParsedLength := ParseInt64(PByte(@Buffer[1]), Length(Buffer), ParsedInt64); // $R-
   Assert(ParsedLength = 0);

   Buffer := '9223372036854775807'; // high(int64)
   ParsedLength := ParseInt64(PByte(@Buffer[1]), Length(Buffer), ParsedInt64); // $R-
   Assert(ParsedLength = Length(Buffer));
   Assert(ParsedInt64 = 9223372036854775807);

   Buffer := '-9223372036854775807'; // -high(int64)
   ParsedLength := ParseInt64(PByte(@Buffer[1]), Length(Buffer), ParsedInt64); // $R-
   Assert(ParsedLength = Length(Buffer));
   Assert(ParsedInt64 = -9223372036854775807);

   Buffer := '-9223372036854775808'; // low(int64)
   ParsedLength := ParseInt64(PByte(@Buffer[1]), Length(Buffer), ParsedInt64); // $R-
   Assert(ParsedLength = Length(Buffer));
   Assert(ParsedInt64 = -9223372036854775808);

   Buffer := '00000000000000000000000000000000000000000000000000';
   ParsedLength := ParseInt64(PByte(@Buffer[1]), Length(Buffer), ParsedInt64); // $R-
   Assert(ParsedLength = Length(Buffer));
   Assert(ParsedInt64 = 0);
end;

procedure TestQuickParseUInt64();
begin
   Assert(ParseUInt64('123') = 123);
   Assert(ParseUInt64('') = 0);
   Assert(ParseUInt64('-123') = 0);
   Assert(ParseUInt64('12a3') = 0);
   Assert(ParseUInt64('12345678901234567890123456789012345678901234567890') = 0);
   Assert(ParseUInt64('18446744073709551620') = 0);
   Assert(ParseUInt64('18446744073709551616') = 0);
   Assert(ParseUInt64('18446744073709551615') = 18446744073709551615);
   Assert(ParseUInt64('00000000000000000000000000000000000000000000000000') = 0);
end;

procedure TestQuickParseInt64();
begin
   Assert(ParseInt64('123') = 123);
   Assert(ParseInt64('') = 0);
   Assert(ParseInt64('-123') = -123);
   Assert(ParseInt64('--123') = 0);
   Assert(ParseInt64('-0') = 0);
   Assert(ParseInt64('12a3') = 0);
   Assert(ParseInt64('12345678901234567890123456789012345678901234567890') = 0);
   Assert(ParseInt64('18446744073709551620') = 0);
   Assert(ParseInt64('18446744073709551616') = 0);
   Assert(ParseInt64('18446744073709551615') = 0);
   Assert(ParseInt64('9223372036854775808') = 0);
   Assert(ParseInt64('9223372036854775807') = 9223372036854775807);
   Assert(ParseInt64('-9223372036854775807') = -9223372036854775807);
   Assert(ParseInt64('-9223372036854775808') = -9223372036854775808);
   Assert(ParseInt64('00000000000000000000000000000000000000000000000000') = 0);
end;

procedure TestParseUInt32();
var
   ParsedUInt32: UInt32;
   ParsedLength: Cardinal;
   Buffer: UTF8String;
begin
   Buffer := '123';
   ParsedLength := ParseUInt32(PByte(@Buffer[1]), Length(Buffer), ParsedUInt32); // $R-
   Assert(ParsedLength = 3);
   Assert(ParsedUInt32 = 123);

   ParsedLength := ParseUInt32(PByte(0), 0, ParsedUInt32); // $R-
   Assert(ParsedLength = 0);

   Buffer := '-123'; // negative (leading garbage)
   ParsedLength := ParseUInt32(PByte(@Buffer[1]), Length(Buffer), ParsedUInt32); // $R-
   Assert(ParsedLength = 0);

   Buffer := '12a3'; // trailing garbage
   ParsedLength := ParseUInt32(PByte(@Buffer[1]), Length(Buffer), ParsedUInt32); // $R-
   Assert(ParsedLength = 2);
   Assert(ParsedUInt32 = 12);

   Buffer := '12345678901234567890123456789012345678901234567890'; // much too long
   ParsedLength := ParseUInt32(PByte(@Buffer[1]), Length(Buffer), ParsedUInt32); // $R-
   Assert(ParsedLength = 0);

   Buffer := '18446744073709551620'; // overflow on multiplication
   ParsedLength := ParseUInt32(PByte(@Buffer[1]), Length(Buffer), ParsedUInt32); // $R-
   Assert(ParsedLength = 0);

   Buffer := '18446744073709551616'; // overflow on addition
   ParsedLength := ParseUInt32(PByte(@Buffer[1]), Length(Buffer), ParsedUInt32); // $R-
   Assert(ParsedLength = 0);

   Buffer := '4294967296'; // overflow on range check
   ParsedLength := ParseUInt32(PByte(@Buffer[1]), Length(Buffer), ParsedUInt32); // $R-
   Assert(ParsedLength = 0);

   Buffer := '4294967295'; // max
   ParsedLength := ParseUInt32(PByte(@Buffer[1]), Length(Buffer), ParsedUInt32); // $R-
   Assert(ParsedLength = Length(Buffer));
   Assert(ParsedUInt32 = 4294967295);

   Buffer := '00000000000000000000000000000000000000000000000000';
   ParsedLength := ParseUInt32(PByte(@Buffer[1]), Length(Buffer), ParsedUInt32); // $R-
   Assert(ParsedLength = Length(Buffer));
   Assert(ParsedUInt32 = 0);
end;

procedure TestParseInt32();
var
   ParsedInt32: Int32;
   ParsedLength: Cardinal;
   Buffer: UTF8String;
begin
   Buffer := '123';
   ParsedLength := ParseInt32(PByte(@Buffer[1]), Length(Buffer), ParsedInt32); // $R-
   Assert(ParsedLength = 3);
   Assert(ParsedInt32 = 123);

   ParsedLength := ParseInt32(PByte(0), 0, ParsedInt32); // $R-
   Assert(ParsedLength = 0);

   Buffer := '-123'; // negative
   ParsedLength := ParseInt32(PByte(@Buffer[1]), Length(Buffer), ParsedInt32); // $R-
   Assert(ParsedLength = 4);
   Assert(ParsedInt32 = -123);

   Buffer := '--123'; // leading garbage
   ParsedLength := ParseInt32(PByte(@Buffer[1]), Length(Buffer), ParsedInt32); // $R-
   Assert(ParsedLength = 0);

   Buffer := '-0';
   ParsedLength := ParseInt32(PByte(@Buffer[1]), Length(Buffer), ParsedInt32); // $R-
   Assert(ParsedLength = 2);
   Assert(ParsedInt32 = 0);

   Buffer := '12a3'; // trailing garbage
   ParsedLength := ParseInt32(PByte(@Buffer[1]), Length(Buffer), ParsedInt32); // $R-
   Assert(ParsedLength = 2);
   Assert(ParsedInt32 = 12);

   Buffer := '12345678901234567890123456789012345678901234567890'; // much too long
   ParsedLength := ParseInt32(PByte(@Buffer[1]), Length(Buffer), ParsedInt32); // $R-
   Assert(ParsedLength = 0);

   Buffer := '18446744073709551620'; // overflow on multiplication
   ParsedLength := ParseInt32(PByte(@Buffer[1]), Length(Buffer), ParsedInt32); // $R-
   Assert(ParsedLength = 0);

   Buffer := '18446744073709551616'; // overflow on addition
   ParsedLength := ParseInt32(PByte(@Buffer[1]), Length(Buffer), ParsedInt32); // $R-
   Assert(ParsedLength = 0);

   Buffer := '18446744073709551615'; // overflow on conversion to signed
   ParsedLength := ParseInt32(PByte(@Buffer[1]), Length(Buffer), ParsedInt32); // $R-
   Assert(ParsedLength = 0);

   Buffer := '9223372036854775808'; // overflow on conversion to signed
   ParsedLength := ParseInt32(PByte(@Buffer[1]), Length(Buffer), ParsedInt32); // $R-
   Assert(ParsedLength = 0);

   Buffer := '9223372036854775807'; // overflow on conversion to signed
   ParsedLength := ParseInt32(PByte(@Buffer[1]), Length(Buffer), ParsedInt32); // $R-
   Assert(ParsedLength = 0);

   Buffer := '-9223372036854775807'; // overflow on conversion to signed
   ParsedLength := ParseInt32(PByte(@Buffer[1]), Length(Buffer), ParsedInt32); // $R-
   Assert(ParsedLength = 0);

   Buffer := '-9223372036854775808'; // overflow on conversion to signed
   ParsedLength := ParseInt32(PByte(@Buffer[1]), Length(Buffer), ParsedInt32); // $R-
   Assert(ParsedLength = 0);

   Buffer := '4294967295'; // overflow on conversion to signed
   ParsedLength := ParseInt32(PByte(@Buffer[1]), Length(Buffer), ParsedInt32); // $R-
   Assert(ParsedLength = 0);

   Buffer := '-2147483649'; // overflow on conversion to signed
   ParsedLength := ParseInt32(PByte(@Buffer[1]), Length(Buffer), ParsedInt32); // $R-
   Assert(ParsedLength = 0);

   Buffer := '2147483647'; // highest value
   ParsedLength := ParseInt32(PByte(@Buffer[1]), Length(Buffer), ParsedInt32); // $R-
   Assert(ParsedLength = Length(Buffer));
   Assert(ParsedInt32 = 2147483647);

   Buffer := '-2147483648'; // lowest value
   ParsedLength := ParseInt32(PByte(@Buffer[1]), Length(Buffer), ParsedInt32); // $R-
   Assert(ParsedLength = Length(Buffer));
   Assert(ParsedInt32 = -2147483648);

   Buffer := '00000000000000000000000000000000000000000000000000';
   ParsedLength := ParseInt32(PByte(@Buffer[1]), Length(Buffer), ParsedInt32); // $R-
   Assert(ParsedLength = Length(Buffer));
   Assert(ParsedInt32 = 0);
end;

procedure TestQuickParseUInt32();
begin
   Assert(ParseUInt32('123') = 123);
   Assert(ParseUInt32('') = 0);
   Assert(ParseUInt32('-123') = 0);
   Assert(ParseUInt32('12a3') = 0);
   Assert(ParseUInt32('12345678901234567890123456789012345678901234567890') = 0);
   Assert(ParseUInt32('18446744073709551620') = 0);
   Assert(ParseUInt32('18446744073709551616') = 0);
   Assert(ParseUInt32('18446744073709551615') = 0);
   Assert(ParseUInt32('4294967296') = 0);
   Assert(ParseUInt32('4294967295') = 4294967295);
   Assert(ParseUInt32('00000000000000000000000000000000000000000000000000') = 0);
end;

procedure TestQuickParseInt32();
begin
   Assert(ParseInt32('123') = 123);
   Assert(ParseInt32('') = 0);
   Assert(ParseInt32('-123') = -123);
   Assert(ParseInt32('--123') = 0);
   Assert(ParseInt32('-0') = 0);
   Assert(ParseInt32('12a3') = 0);
   Assert(ParseInt32('12345678901234567890123456789012345678901234567890') = 0);
   Assert(ParseInt32('18446744073709551620') = 0);
   Assert(ParseInt32('18446744073709551616') = 0);
   Assert(ParseInt32('18446744073709551615') = 0);
   Assert(ParseInt32('9223372036854775808') = 0);
   Assert(ParseInt32('9223372036854775807') = 0);
   Assert(ParseInt32('-9223372036854775807') = 0);
   Assert(ParseInt32('-9223372036854775808') = 0);
   Assert(ParseInt32('4294967295') = 0);
   Assert(ParseInt32('-2147483649') = 0);
   Assert(ParseInt32('2147483647') = 2147483647);
   Assert(ParseInt32('-2147483648') = -2147483648);
   Assert(ParseInt32('00000000000000000000000000000000000000000000000000') = 0);
end;
{$ENDIF}

initialization
   {$IFDEF TESTS}
      TestParseUInt64();
      TestParseInt64();
      TestQuickParseUInt64();
      TestQuickParseInt64();
      TestParseUInt32();
      TestParseInt32();
      TestQuickParseUInt32();
      TestQuickParseInt32();
   {$ENDIF}
end.
