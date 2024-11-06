{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit random;

// This is an implementation of the 32 bit PCG-XSH-RR generator with 64 bits of state.
// See pcg-random.org.

interface

type
   TPerturbationParameters = record
      ProbabilityZero: Double; // 0.0 .. 1.0
      ProbabilityRandomize, RandomizeMin, RandomizeMax: Double;
   end;

   TRandomNumberGenerator = class
   private
      var
         FState: UInt64;
         FIncrement: UInt64;
      const
         FMultiplier: UInt64 = 6364136223846793005; // magic constant widely used as LCG multiplier
   public
      constructor Create(ASeed: UInt32);
      procedure Reset(NewState: UInt64);
      function GetUInt32(): UInt32; // uniform 0..High(UInt32)
      function GetDouble(Min, Max: Double): Double; // uniform Min..Max (inclusive, exclusive)
      function GetBoolean(Probability: Double): Boolean; // P(True) = Probability (0..1)
      function Perturb(Value: Double; const Parameters: TPerturbationParameters): Double;
      property State: UInt64 read FState;
   end;

const
   NormalPerturbation: TPerturbationParameters = (
      ProbabilityZero: 0.0;
      ProbabilityRandomize: 0.0;
      RandomizeMin: 0.0;
      RandomizeMax: 0.0
   );
   
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
   
procedure TRandomNumberGenerator.Reset(NewState: UInt64);
begin
   FState := NewState;
end;

function TRandomNumberGenerator.GetUInt32(): UInt32;
begin
   {$PUSH}
   {$OVERFLOWCHECKS-}
   {$RANGECHECKS-}
   FState := FState * FMultiplier + FIncrement;
   Result := RoRDWord((FState xor (FState >> 18)) >> 27, FState >> 59); // $R- // first arguments intentionally drops some high bits
   {$POP}
end;

function TRandomNumberGenerator.GetDouble(Min, Max: Double): Double;
begin
   Result := Min + (Max - Min) * GetUInt32() / High(UInt32);
end;

function TRandomNumberGenerator.GetBoolean(Probability: Double): Boolean;
begin
   Result := GetUInt32() / (High(UInt32) + 1) < Probability;
end;

function TRandomNumberGenerator.Perturb(Value: Double; const Parameters: TPerturbationParameters): Double;

   // returns a number 0..1 that's most likely to be near 0.5
   function GetAdjustedDouble(): Double; inline;
   begin
      // y = ((2x-1)^3+1)/2
      Result := GetDouble(0.0, 1.0);
      Result := 2 * Result - 1;
      Result := Result * Result * Result + 1;
      Result := Result / 2;
   end;

var
   R: Double;
begin
   Assert(Parameters.ProbabilityZero >= 0.0);
   Assert(Parameters.ProbabilityRandomize >= 0.0);
   Assert(Parameters.ProbabilityZero + Parameters.ProbabilityRandomize <= 1.0);
   R := GetDouble(0.0, 1.0);
   if (R < Parameters.ProbabilityZero) then
   begin
      Result := 0.0;
      exit;
   end;
   if (R < Parameters.ProbabilityZero + Parameters.ProbabilityRandomize) then
   begin
      Result := GetDouble(Parameters.RandomizeMin, Parameters.RandomizeMax);
      exit;
   end;
   Result := GetAdjustedDouble() * 2.0 * Value;
end;

end.