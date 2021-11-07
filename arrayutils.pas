{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit arrayutils;

interface

// Use as follows:
// FisherYatesShuffle(ArrayToShuffle[Low(ArrayToShuffle)], Length(ArrayToShuffle), SizeOf(ArrayToShuffle[0]));
procedure FisherYatesShuffle(var Buffer; const Count: Cardinal; const ElementSize: Cardinal);

function Join(const Input: array of RawByteString; const Separator: RawByteString): RawByteString;

implementation

procedure FisherYatesShuffle(var Buffer; const Count: Cardinal; const ElementSize: Cardinal);
var
   Index, Subindex: Cardinal;
   Temp: Pointer;
begin
   if (Count < 2) then
      Exit;
   GetMem(Temp, ElementSize);
   for Index := Count-1 downto 1 do // $R-
   begin
      Subindex := Random(Index+1); // $R-
      {$POINTERMATH ON}
      Move((@Buffer+Subindex*ElementSize)^, Temp^, ElementSize);
      Move((@Buffer+Index*ElementSize)^, (@Buffer+Subindex*ElementSize)^, ElementSize);
      Move(Temp^, (@Buffer+Index*ElementSize)^, ElementSize);
      {$POINTERMATH OFF}
   end;
   FreeMem(Temp, ElementSize);
end;

function Join(const Input: array of RawByteString; const Separator: RawByteString): RawByteString;
var
   Index: Cardinal;
   Value: RawByteString;
begin
   Index := 0;
   for Value in Input do
      Inc(Index, Length(Value));
   SetLength(Result, Index + (Length(Input) - 1) * Length(Separator)); // {BOGUS Hint: Function result variable of a managed type does not seem to be initialized}
   Index := 1;
   for Value in Input do
   begin
      if (Length(Value) > 0) then
      begin
         if ((Index > 1) and (Length(Separator) > 0)) then
         begin
            Move(Separator[1], Result[Index], Length(Separator));
            Inc(Index, Length(Separator));
         end;
         Move(Value[1], Result[Index], Length(Value));
         Inc(Index, Length(Value));
      end;  
   end;
end;
   
end.
