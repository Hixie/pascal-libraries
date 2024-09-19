{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit random;

// This is an implementation of the 32 bit PCG-XSH-RR generator with 64 bits of state.
// See pcg-random.org.

interface

type
   TRandomNumberGenerator = class
   private
      var
         FState: UInt64;
         FIncrement: UInt64;
      const
         FMultiplier: UInt64 = 6364136223846793005; // magic constant widely used as LCG multiplier
   public
      constructor Create(ASeed: UInt32);
      procedure Reset(NewState: UInt32);
      function GetUInt32(): UInt32;
      property State: UInt64 read FState;
   end;

implementation

constructor TRandomNumberGenerator.Create(ASeed: UInt32);
begin
   inherited Create();
   {$PUSH}
   {$OVERFLOWCHECKS-}
   {$RANGECHECKS-}
   FIncrement := (ASeed << 1) + 1; // must be an odd number // $R- (we might drop the top bit)
   {$POP}
   FState := FIncrement;
end;
   
procedure TRandomNumberGenerator.Reset(NewState: UInt32);
begin
   FState := NewState;
end;

function TRandomNumberGenerator.GetUInt32(): UInt32;
begin
   {$PUSH}
   {$OVERFLOWCHECKS-}
   {$RANGECHECKS-}
   FState := FState * FMultiplier + FIncrement;
   Result := RoRDWord((FState xor (FState >> 18)) >> 27, FState >> 59); // $R-
   {$POP}
end;

end.