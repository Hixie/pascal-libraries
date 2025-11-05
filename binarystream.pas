{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit binarystream;

interface

uses
   sysutils;

type
   TBinaryStreamReader = class
   private
      FInput: RawByteString;
      FPosition: Cardinal; // 1-based
      procedure CheckCanRead(ComponentSize: Cardinal); inline;
   public
      constructor Create(const Input: RawByteString);
      function ReadBoolean(): Boolean;
      function ReadCardinal(): Cardinal;
      function ReadPtrUInt(): PtrUInt;
      function ReadByte(): Byte;
      function ReadInt32(): Int32;
      function ReadInt64(): Int64;
      function ReadUInt64(): UInt64;
      function ReadDouble(): Double;
      function ReadString(): RawByteString;
      function ReadBytes(): TBytes;
      procedure ReadEnd();
      procedure ReadRawBytes(Length: Cardinal; out Output);
      procedure Reset(); // returns position to start
      procedure Truncate(Remainder: Cardinal); // truncates the input so that only Remainder bytes remain
      property RawInput: RawByteString read FInput;
   end;

   TBinaryStreamWriter = class
   private
      const
         SegmentSize = 1024;
      type
         PSegment = ^TSegment;
         TSegment = record
         public
            procedure Init(Size: Cardinal); // Size is how much memory was allocated (>= SizeOf(TSegment), by definition)
         public
            Next: PSegment; // must be first in record
            Length, BufferSize: Cardinal; // BufferSize is the size of the buffer _if it is mutable_.
            Buffer: Pointer;
            BufferStart: record end; // must be last in record
            // if the PSegment expects to have a buffer, it will be allocated with extra space here
         end;
      var
         FFirst: PSegment;
         FLast: PSegment;
         FPosition: Cardinal; // position in FLast, 0-based
         FLength: Cardinal; // total length so far
         FSkip: Cardinal; // leading bytes to skip
      function GetReferenceSegment(BufferLength: Cardinal): PSegment; // allocates a TSegment with no buffer
      function GetDestination(NeededLength: Cardinal): Pointer; // returns pointer to mutable part of a TSegment's buffer
   public
      destructor Destroy(); override;
      procedure WriteBoolean(const Value: Boolean);
      procedure WriteCardinal(const Value: Cardinal);
      procedure WritePtrUInt(const Value: PtrUInt);
      procedure WriteByte(const Value: Byte);
      procedure WriteInt32(const Value: Int32);
      procedure WriteInt64(const Value: Int64);
      procedure WriteUInt64(const Value: UInt64);
      procedure WriteDouble(const Value: Double);
      procedure WriteString(const Value: RawByteString); // expensive
      procedure WriteBytes(const Value: TBytes); // expensive
      procedure WriteRawBytes(Buffer: Pointer; Length: Cardinal); // expensive
      procedure WriteStringByPointer(const Value: RawByteString); // STRING MUST REMAIN VALID UNTIL CALL TO SERIALIZE
      procedure WriteBytesByPointer(const Value: TBytes); // ARRAY MUST REMAIN VALID UNTIL CALL TO SERIALIZE
      procedure WriteRawBytesByPointer(Buffer: Pointer; Length: Cardinal); // POINTER MUST REMAIN VALID UNTIL CALL TO SERIALIZE
      function Serialize(IncludeLengthPrefix: Boolean): RawByteString;
      procedure Consume(Count: Cardinal); // skips the leading Count bytes in future Serialize attempts
      procedure Clear(); // consume everything
      property BufferLength: Cardinal read FLength;
   end;

   EBinaryStreamError = class(Exception)
   end;

// TODO: build a version of this that uses the same API for reading and writing so that you can have just one codepath
   
implementation

constructor TBinaryStreamReader.Create(const Input: RawByteString);
begin
   inherited Create();
   FInput := Input;
   FPosition := 1;
end;

procedure TBinaryStreamReader.CheckCanRead(ComponentSize: Cardinal);
begin
   if (FPosition + ComponentSize - 1 > Length(FInput)) then
      raise EBinaryStreamError.CreateFmt('Read past end of stream (position=%d, size=%d, length=%d).', [FPosition, ComponentSize, Length(FInput)]);
end;

function TBinaryStreamReader.ReadBoolean(): Boolean;
type
   PByteBool = ^ByteBool;
begin
   CheckCanRead(SizeOf(ByteBool));
   Result := PByteBool(Pointer(@FInput[FPosition]))^;
   Inc(FPosition, 1);
end;

function TBinaryStreamReader.ReadCardinal(): Cardinal;
type
   PCardinal = ^Cardinal;
begin
   CheckCanRead(SizeOf(Cardinal));
   Result := PCardinal(Pointer(@FInput[FPosition]))^;
   Inc(FPosition, SizeOf(Cardinal));
end;

function TBinaryStreamReader.ReadPtrUInt(): PtrUInt;
type
   PPtrUInt = ^PtrUInt;
begin
   CheckCanRead(SizeOf(PtrUInt));
   Result := PPtrUInt(Pointer(@FInput[FPosition]))^;
   Inc(FPosition, SizeOf(PtrUInt));
end;

function TBinaryStreamReader.ReadByte(): Byte;
type
   PByte = ^Byte;
begin
   CheckCanRead(SizeOf(Byte));
   Result := PByte(Pointer(@FInput[FPosition]))^;
   Inc(FPosition, SizeOf(Byte));
end;

function TBinaryStreamReader.ReadInt32(): Int32;
type
   PInt32 = ^Int32;
begin
   CheckCanRead(SizeOf(Int32));
   Result := PInt32(Pointer(@FInput[FPosition]))^;
   Inc(FPosition, SizeOf(Int32));
end;

function TBinaryStreamReader.ReadInt64(): Int64;
type
   PInt64 = ^Int64;
begin
   CheckCanRead(SizeOf(Int64));
   Result := PInt64(Pointer(@FInput[FPosition]))^;
   Inc(FPosition, SizeOf(Int64));
end;

function TBinaryStreamReader.ReadUInt64(): UInt64;
type
   PUInt64 = ^UInt64;
begin
   CheckCanRead(SizeOf(UInt64));
   Result := PUInt64(Pointer(@FInput[FPosition]))^;
   Inc(FPosition, SizeOf(UInt64));
end;

function TBinaryStreamReader.ReadDouble(): Double;
type
   PDouble = ^Double;
begin
   CheckCanRead(SizeOf(Double));
   Result := PDouble(Pointer(@FInput[FPosition]))^;
   Inc(FPosition, SizeOf(Double));
end;

function TBinaryStreamReader.ReadString(): RawByteString;
var
   BufferLength: Cardinal;
begin
   BufferLength := ReadCardinal();
   CheckCanRead(SizeOf(BufferLength));
   SetLength(Result, BufferLength); {BOGUS Hint: Function result variable of a managed type does not seem to be initialized}
   if (BufferLength > 0) then
   begin
      Move(FInput[FPosition], Result[1], BufferLength);
      Inc(FPosition, BufferLength);
   end;
end;

function TBinaryStreamReader.ReadBytes(): TBytes;
var
   BufferLength: Cardinal;
begin
   BufferLength := ReadCardinal();
   CheckCanRead(SizeOf(BufferLength));
   SetLength(Result, BufferLength); {BOGUS Warning: Function result variable of a managed type does not seem to be initialized}
   if (BufferLength > 0) then
   begin
      Move(FInput[FPosition], Result[0], BufferLength);
      Inc(FPosition, BufferLength);
   end;
end;

procedure TBinaryStreamReader.ReadRawBytes(Length: Cardinal; out Output);
begin
   CheckCanRead(SizeOf(Length));
   if (Length > 0) then
   begin
      Move(FInput[FPosition], Output, Length); {BOGUS Hint: Variable "Output" does not seem to be initialized}
      Inc(FPosition, Length);
   end;
end;

procedure TBinaryStreamReader.ReadEnd();
begin
   if (FPosition <> Length(FInput) + 1) then
      raise EBinaryStreamError.CreateFmt('Unexpected trailing data (position=%d, length=%d).', [FPosition, Length(FInput)]);
end;

procedure TBinaryStreamReader.Reset();
begin
   FPosition := 1;
end;

procedure TBinaryStreamReader.Truncate(Remainder: Cardinal);
begin
   Assert((FPosition - 1) + Remainder <= Length(FInput));
   SetLength(FInput, (FPosition - 1) + Remainder);
end;


procedure TBinaryStreamWriter.TSegment.Init(Size: Cardinal);
begin
   Assert(Size >= SizeOf(TSegment));
   Next := nil;
   Length := 0;
   if (Size = SizeOf(TSegment)) then
   begin
      Buffer := nil;
      BufferSize := 0;
   end
   else
   begin
      Buffer := @BufferStart;
      Assert(PtrUInt(@BufferStart) - PtrUInt(@Next) = SizeOf(TSegment));
      Assert(Size > SizeOf(TSegment));
      BufferSize := Size - SizeOf(TSegment); // $R-
   end;
end;

destructor TBinaryStreamWriter.Destroy();
var
   Next: PSegment;
begin
   while (Assigned(FFirst)) do
   begin
      Next := FFirst^.Next;
      FreeMem(FFirst);
      FFirst := Next;
   end;      
   inherited;
end;

function TBinaryStreamWriter.GetReferenceSegment(BufferLength: Cardinal): PSegment;
begin
   if (not Assigned(FLast)) then
   begin
      FFirst := GetMem(SizeOf(TSegment));
      FFirst^.Init(SizeOf(TSegment));
      FLast := FFirst;
      FLast^.Next := nil;
      Assert(FPosition = 0);
   end
   else
   begin
      FLast^.Next := GetMem(SizeOf(TSegment));
      FLast := FLast^.Next;
      FLast^.Init(SizeOf(TSegment));
      FPosition := 0;
   end;
   Result := FLast;
   FLast^.Length := BufferLength;
   Inc(FLength, BufferLength);
end;

function TBinaryStreamWriter.GetDestination(NeededLength: Cardinal): Pointer;
var
   BufferSize: Cardinal;
begin
   Assert(NeededLength > 0);
   if (NeededLength > SegmentSize - SizeOf(TSegment)) then
   begin
      BufferSize := NeededLength + SizeOf(TSegment); // $R-
   end
   else
   begin
      BufferSize := SegmentSize;
   end;
   if (not Assigned(FLast)) then
   begin
      FFirst := GetMem(BufferSize);
      FLast := FFirst;
      FLast^.Init(BufferSize);
      FLast^.Next := nil;
      Assert(FPosition = 0);
   end
   else
   if (NeededLength >= FLast^.BufferSize - FPosition) then
   begin
      FLast^.Next := GetMem(BufferSize);
      FLast := FLast^.Next;
      FLast^.Init(BufferSize);
      FPosition := 0;
   end;
   Result := FLast^.Buffer + FPosition;
   Inc(FLast^.Length, NeededLength);
   Inc(FPosition, NeededLength);
   Inc(FLength, NeededLength);
end;

procedure TBinaryStreamWriter.WriteBoolean(const Value: Boolean);
begin
   if (Value) then
   begin
      PByte(GetDestination(1))^ := $01;
   end
   else
   begin
      PByte(GetDestination(1))^ := $00;
   end;
end;

procedure TBinaryStreamWriter.WriteCardinal(const Value: Cardinal);
type
   PCardinal = ^Cardinal;
begin
   PCardinal(GetDestination(SizeOf(Cardinal)))^ := Value;
end;

procedure TBinaryStreamWriter.WritePtrUInt(const Value: PtrUInt);
type
   PPtrUInt = ^PtrUInt;
begin
   PPtrUInt(GetDestination(SizeOf(PtrUInt)))^ := Value;
end;

procedure TBinaryStreamWriter.WriteByte(const Value: Byte);
type
   PByte = ^Byte;
begin
   PByte(GetDestination(SizeOf(Byte)))^ := Value;
end;

procedure TBinaryStreamWriter.WriteInt32(const Value: Int32);
type
   PInt32 = ^Int32;
begin
   PInt32(GetDestination(SizeOf(Int32)))^ := Value;
end;

procedure TBinaryStreamWriter.WriteInt64(const Value: Int64);
type
   PInt64 = ^Int64;
begin
   PInt64(GetDestination(SizeOf(Int64)))^ := Value;
end;

procedure TBinaryStreamWriter.WriteUInt64(const Value: UInt64);
type
   PUInt64 = ^UInt64;
begin
   PUInt64(GetDestination(SizeOf(UInt64)))^ := Value;
end;

procedure TBinaryStreamWriter.WriteDouble(const Value: Double);
type
   PDouble = ^Double;
begin
   PDouble(GetDestination(SizeOf(Double)))^ := Value;
end;

procedure TBinaryStreamWriter.WriteStringByPointer(const Value: RawByteString);
begin
   WriteCardinal(Length(Value));
   if (Value <> '') then
   begin
      WriteRawBytesByPointer(@Value[1], Length(Value)); // $R-
   end;
end;

procedure TBinaryStreamWriter.WriteBytesByPointer(const Value: TBytes);
begin
   WriteCardinal(Length(Value));
   if (Length(Value) > 0) then
      WriteRawBytesByPointer(@Value[0], Length(Value)); // $R-
end;

procedure TBinaryStreamWriter.WriteRawBytesByPointer(Buffer: Pointer; Length: Cardinal);
begin
   if (Length > FLast^.BufferSize - FPosition) then
   begin
      GetReferenceSegment(Length)^.Buffer := Buffer;
   end
   else
   if (Length > 0) then
   begin
      Move(Buffer^, GetDestination(Length)^, Length);
   end;
end;

procedure TBinaryStreamWriter.WriteString(const Value: RawByteString);
begin
   WriteCardinal(Length(Value));
   if (Value <> '') then
      WriteRawBytes(@Value[1], Length(Value)); // $R-
end;

procedure TBinaryStreamWriter.WriteBytes(const Value: TBytes);
begin
   WriteCardinal(Length(Value));
   if (Length(Value) > 0) then
      WriteRawBytes(@Value[0], Length(Value)); // $R-
end;

procedure TBinaryStreamWriter.WriteRawBytes(Buffer: Pointer; Length: Cardinal);
begin
   Move(Buffer^, GetDestination(Length)^, Length);
end;

function TBinaryStreamWriter.Serialize(IncludeLengthPrefix: Boolean): RawByteString;
var
   Buffer: RawByteString;
   Index, Skip: Cardinal;
   Segment: PSegment;
begin
   Index := 1;
   if (IncludeLengthPrefix) then
   begin
      SetLength(Buffer, SizeOf(Cardinal) + FLength);
      Move(FLength, Buffer[Index], SizeOf(Cardinal));
      Inc(Index, SizeOf(Cardinal));
   end
   else
   begin
      SetLength(Buffer, FLength);
   end;
   Segment := FFirst;
   Skip := FSkip;
   while (Assigned(Segment)) do
   begin
      Assert(Skip < Segment^.Length);
      Move((Segment^.Buffer + Skip)^, Buffer[Index], Segment^.Length - Skip);
      Inc(Index, Segment^.Length - Skip);
      Segment := Segment^.Next;
      Skip := 0;
   end;
   Assert(Index = Length(Buffer) + 1);
   Result := Buffer;
end;

procedure TBinaryStreamWriter.Consume(Count: Cardinal);
var
   Segment: PSegment;
begin
   Assert(Count <= FLength);
   Inc(FSkip, Count);
   Dec(FLength, Count);
   while (Assigned(FFirst) and (FFirst^.Length <= FSkip)) do
   begin
      Segment := FFirst;
      FFirst := FFirst^.Next;
      Dec(FSkip, Segment^.Length);
      if (FLast = Segment) then
      begin
         FLast := nil;
         FPosition := 0;
         Assert(not Assigned(FFirst));
      end;
      FreeMem(Segment);
   end;
end;

procedure TBinaryStreamWriter.Clear();
var
   Segment: PSegment;
begin
   while (Assigned(FFirst)) do
   begin
      Segment := FFirst;
      FFirst := FFirst^.Next;
      FreeMem(Segment);
   end;
   FLast := nil;
   FPosition := 0;
   FLength := 0;
   FSkip := 0;
end;

end.
