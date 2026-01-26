{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit random;

// This is an implementation of the 32 bit PCG-XSH-RR generator with 64 bits of state.
// See pcg-random.org.

//{$DEFINE VERBOSE}

interface

type
   TPerturbationParameters = record
      ProbabilityZero: Double; // 0.0 .. 1.0
      ProbabilityRandomize, RandomizeMin, RandomizeMax: Double;
   end;

   TRandomNumberGenerator = class
   strict private
      function InternalRNG(): UInt32;
   private
      var
         FState: UInt64;
         FIncrement: UInt64; // this is essentially the seed (63 bits of entropy, the lowest bit is always 1)
      const
         FMultiplier: UInt64 = 6364136223846793005; // magic constant widely used as LCG multiplier
      function GetSeed(): UInt64;
   public
      constructor Create(ASeed: UInt64); // high bit of seed is dropped
      procedure Reset(NewState: UInt64);
      function GetUInt32(): UInt32; inline; // uniform 0..High(UInt32)
      function GetCardinal(Min, Max: Cardinal): Cardinal; // uniform Min..Max (inclusive, exclusive)
      function GetDouble(Min, Max: Double): Double; // uniform Min..Max (inclusive, exclusive)
      function GetBoolean(Probability: Double): Boolean; // P(True) = Probability (0..1)
      function Perturb(Value: Double; const Parameters: TPerturbationParameters): Double;
      property State: UInt64 read FState;
      property Seed: UInt64 read GetSeed;
   end;

const
   NormalPerturbation: TPerturbationParameters = (
      ProbabilityZero: 0.0;
      ProbabilityRandomize: 0.0;
      RandomizeMin: 0.0;
      RandomizeMax: 0.0
   );
   
implementation

function TRandomNumberGenerator.InternalRNG(): UInt32;

   {$IFDEF VERBOSE}
   procedure Log();
   var
      LogStackFrame, InternalRNGStackFrame, APIStackFrame: Pointer;
   begin
      LogStackFrame := Get_Frame;
      InternalRNGStackFrame := Get_Caller_Frame(LogStackFrame);
      APIStackFrame := Get_Caller_Frame(InternalRNGStackFrame);
      Assert(Assigned(APIStackFrame));
      Writeln('RNG for ', BackTraceStrFunc(Get_Caller_Addr(APIStackFrame)), ' at state ', FState);
   end;
   {$ENDIF}

begin
   {$IFDEF VERBOSE} Log(); {$ENDIF}
   {$PUSH}
   {$OVERFLOWCHECKS-}
   {$RANGECHECKS-}
   FState := FState * FMultiplier + FIncrement;
   Result := RoRDWord((FState xor (FState >> 18)) >> 27, FState >> 59); // $R- // first argument intentionally drops some high bits
   {$POP}
end;
   
constructor TRandomNumberGenerator.Create(ASeed: UInt64);
begin
   inherited Create();
   {$PUSH}
   {$OVERFLOWCHECKS-}
   {$RANGECHECKS-}
   FIncrement := (ASeed << 1) + 1; // must be an odd number // $R- (we drop the high bit)
   {$POP}
   FState := FIncrement;
end;
   
function TRandomNumberGenerator.GetSeed(): UInt64;
begin
   Result := FIncrement >> 1;
end;

procedure TRandomNumberGenerator.Reset(NewState: UInt64);
begin
   FState := NewState;
end;

function TRandomNumberGenerator.GetUInt32(): UInt32;
begin
   Result := InternalRNG();
end;

function TRandomNumberGenerator.GetCardinal(Min, Max: Cardinal): Cardinal;
begin
   Result := Min + Trunc((Max - Min) * InternalRNG() / (High(UInt32) + 1)); // $R-
end;

function TRandomNumberGenerator.GetDouble(Min, Max: Double): Double;
begin
   Result := Min + (Max - Min) * InternalRNG() / (High(UInt32) + 1.0);
end;

function TRandomNumberGenerator.GetBoolean(Probability: Double): Boolean;
begin
   Result := InternalRNG() / (High(UInt32) + 1) < Probability;
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