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
   public
      constructor Create(const Input: RawByteString);
      function ReadBoolean(): Boolean;
      function ReadCardinal(): Cardinal;
      function ReadDouble(): Double;
      function ReadString(): RawByteString;
      function ReadBytes(): TBytes;
      procedure ReadRawBytes(Length: Cardinal; out Output);
      procedure Reset(); // returns position to start
      procedure Truncate(Remainder: Cardinal); // truncates the input so that only Remainder bytes remain
   end;

   TBinaryStreamWriter = class
   private
      const
         SegmentSize = 1024;
      type
         PSegment = ^TSegment;
         TSegment = record
            Next: PSegment;
            Data: array[0..SegmentSize-1] of Byte;
            Length: Cardinal;
            procedure Reset();
         end;
      var
         FFirst: PSegment;
         FLast: PSegment;
         FPosition: Cardinal; // position in FLast, 0-based
         FLength: Cardinal; // total length so far
         FSkip: Cardinal; // leading bytes to skip
      function GetDestination(NeededLength: Cardinal): Pointer;
   public
      destructor Destroy(); override;
      procedure WriteBoolean(const Value: Boolean);
      procedure WriteCardinal(const Value: Cardinal);
      procedure WriteDouble(const Value: Double);
      procedure WriteString(const Value: RawByteString);
      procedure WriteBytes(const Value: TBytes);
      procedure WriteRawBytes(Buffer: Pointer; Length: Cardinal);
      function Serialize(IncludeLengthPrefix: Boolean): RawByteString;
      procedure Consume(Count: Cardinal); // skips the leading Count bytes in future Serialize attempts
      property BufferLength: Cardinal read FLength;
   end;

implementation

constructor TBinaryStreamReader.Create(const Input: RawByteString);
begin
   inherited Create();
   FInput := Input;
   FPosition := 1;
end;

function TBinaryStreamReader.ReadBoolean(): Boolean;
type
   PByteBool = ^ByteBool;
begin
   Result := PByteBool(Pointer(@FInput[FPosition]))^;
   Inc(FPosition, 1);
end;

function TBinaryStreamReader.ReadCardinal(): Cardinal;
type
   PCardinal = ^Cardinal;
begin
   Result := PCardinal(Pointer(@FInput[FPosition]))^;
   Inc(FPosition, SizeOf(Cardinal));
end;

function TBinaryStreamReader.ReadDouble(): Double;
type
   PDouble = ^Double;
begin
   Result := PDouble(Pointer(@FInput[FPosition]))^;
   Inc(FPosition, SizeOf(Double));
end;

function TBinaryStreamReader.ReadString(): RawByteString;
var
   BufferLength: Cardinal;
begin
   BufferLength := ReadCardinal();
   SetLength(Result, BufferLength);
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
   SetLength(Result, BufferLength);
   if (BufferLength > 0) then
   begin
      Move(FInput[FPosition], Result[0], BufferLength);
      Inc(FPosition, BufferLength);
   end;
end;

procedure TBinaryStreamReader.ReadRawBytes(Length: Cardinal; out Output);
begin
   if (Length > 0) then
   begin
      Move(FInput[FPosition], Output, Length);
      Inc(FPosition, Length);
   end;
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


procedure TBinaryStreamWriter.TSegment.Reset();
begin
   Next := nil;
   Length := 0;
end;


destructor TBinaryStreamWriter.Destroy();
var
   Next: PSegment;
begin
   while (Assigned(FFirst)) do
   begin
      Next := FFirst^.Next;
      Dispose(FFirst);
      FFirst := Next;
   end;      
   inherited;
end;

function TBinaryStreamWriter.GetDestination(NeededLength: Cardinal): Pointer;
begin
   Assert(NeededLength > 0);
   Assert(NeededLength <= SegmentSize);
   if (not Assigned(FLast)) then
   begin
      New(FFirst);
      FFirst^.Reset();
      FLast := FFirst;
      FLast^.Next := nil;
      Assert(FPosition = 0);
   end
   else
   if (FPosition + NeededLength >= High(FLast^.Data)) then
   begin
      New(FLast^.Next);
      FLast := FLast^.Next;
      FLast^.Reset();
      FPosition := 0;
   end;
   Result := Pointer(@FLast^.Data) + FPosition;
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

procedure TBinaryStreamWriter.WriteDouble(const Value: Double);
type
   PDouble = ^Double;
begin
   PDouble(GetDestination(SizeOf(Double)))^ := Value;
end;

procedure TBinaryStreamWriter.WriteRawBytes(Buffer: Pointer; Length: Cardinal);
var
   ChunkSize: Cardinal;
begin
   while (Length > 0) do
   begin
      Assert(FPosition <= SegmentSize);
      ChunkSize := SegmentSize - FPosition; // $R-
      if (ChunkSize = 0) then
      begin
         ChunkSize := SegmentSize;
      end;
      if (ChunkSize > Length) then
      begin
         ChunkSize := Length;
      end;
      Move(Buffer^, GetDestination(ChunkSize)^, ChunkSize);
      Inc(Buffer, ChunkSize);
      Dec(Length, ChunkSize);
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
      Move(Segment^.Data[Skip], Buffer[Index], Segment^.Length - Skip);
      Inc(Index, Segment^.Length);
      Segment := Segment^.Next;
      Skip := 0;
   end;
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
      end;
      Dispose(Segment);
   end;
end;

end.
